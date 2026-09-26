import '../../../../core/error/app_failure.dart';
import '../../../../core/result/result.dart';
import '../models/app_user.dart';
import '../models/auth_identity.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_repository.dart';
import '../validation/auth_input_validation.dart';

/// Outcome of a registration attempt.
///
/// Registration spans **two** systems (Firebase Authentication and Firestore), so
/// a single success/failure flag could not describe what actually happened. The
/// SRS requires that a failure to create the profile is never reported as a
/// successful registration (Phase 4 Task 5).
sealed class RegistrationResult {
  const RegistrationResult();
}

/// The account **and** its profile both exist.
final class RegistrationComplete extends RegistrationResult {
  const RegistrationComplete({required this.identity, required this.profile});

  /// The identity that was created.
  final AuthIdentity identity;

  /// The stored profile.
  final AppUser profile;
}

/// Nothing was created: validation failed, or the account could not be created.
final class RegistrationRejected extends RegistrationResult {
  const RegistrationRejected(this.failure);

  final AppFailure failure;
}

/// The account exists but its profile could not be stored.
///
/// Recovery strategy (see `docs/decisions/ADR-008-identity-profile-separation.md`):
/// the session is **kept**, the account is **not** deleted, and the missing
/// profile is handled as a first-class state — the profile screen offers to
/// finish setup, and the dashboard states that setup is incomplete. Re-running
/// [AuthService.register] is unnecessary: signing in later reaches the same
/// recovery path, and `ProfileRepository.createProfile` is idempotent.
final class RegistrationProfilePending extends RegistrationResult {
  const RegistrationProfilePending(this.identity, this.failure);

  /// The identity that now exists.
  final AuthIdentity identity;

  /// Why the profile could not be stored.
  final AppFailure failure;
}

/// Coordinates identity and profile so callers do not have to.
///
/// Pure Dart: it depends only on the two repository interfaces, which makes the
/// multi-system registration flow unit-testable with fakes and keeps the
/// orchestration out of the widgets (constraint 4).
class AuthService {
  const AuthService({required this.auth, required this.profiles});

  final AuthRepository auth;
  final ProfileRepository profiles;

  /// Whether an account service is configured and reachable.
  bool get isAvailable => auth.isAvailable;

  /// Creates an account and, on success, its profile document.
  ///
  /// Order matters: the profile is keyed by the uid, so the account must exist
  /// first. The profile write is idempotent, so a retry after a partial failure
  /// cannot create a duplicate (SRS Task 5).
  Future<RegistrationResult> register({
    required String email,
    required String password,
    required String confirmPassword,
    required String displayName,
  }) async {
    final validationFailure = AuthInputValidation.firstFailure([
      AuthInputValidation.displayName(displayName),
      AuthInputValidation.email(email),
      AuthInputValidation.password(password),
      AuthInputValidation.confirmPassword(confirmPassword, password: password),
    ]);
    if (validationFailure != null) {
      return RegistrationRejected(validationFailure);
    }

    final identityResult = await auth.registerWithEmail(
      email: email.trim(),
      password: password,
    );

    final AuthIdentity identity;
    switch (identityResult) {
      case Success<AuthIdentity>(:final value):
        identity = value;
      case Failure<AuthIdentity>(:final failure):
        // Nothing exists yet, so the caller may safely retry the whole form.
        return RegistrationRejected(failure);
    }

    final profileResult = await profiles.createProfile(
      uid: identity.uid,
      displayName: displayName.trim(),
    );

    return switch (profileResult) {
      Success<AppUser>(:final value) => RegistrationComplete(
        identity: identity,
        profile: value,
      ),
      Failure<AppUser>(:final failure) => RegistrationProfilePending(
        identity,
        failure,
      ),
    };
  }

  /// Authenticates an existing account.
  ///
  /// Validates input first so an obviously malformed request never reaches the
  /// network, then returns the provider's identity. The profile is loaded
  /// separately (`currentUserProfileProvider`), because a missing profile must be
  /// representable without blocking sign-in (Phase 4 Task 14).
  Future<Result<AuthIdentity>> signIn({
    required String email,
    required String password,
  }) async {
    final validationFailure = AuthInputValidation.firstFailure([
      AuthInputValidation.email(email),
      AuthInputValidation.password(password),
    ]);
    if (validationFailure != null) {
      return Failure<AuthIdentity>(validationFailure);
    }

    return auth.signInWithEmail(email: email.trim(), password: password);
  }

  /// Ends the session. Never deletes the account or the profile (SRS Task 7).
  Future<Result<void>> signOut() => auth.signOut();

  /// Reads the profile for [uid].
  ///
  /// `Success(null)` means the document genuinely does not exist.
  Future<Result<AppUser?>> loadProfile(String uid) => profiles.getProfile(uid);
}
