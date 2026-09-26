import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/firebase/firebase_providers.dart';
import '../../../../core/result/result.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/firestore_profile_repository.dart';
import '../../data/repositories/unavailable_auth_repository.dart';
import '../../data/repositories/unavailable_profile_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/auth_identity.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/services/auth_service.dart';
import 'auth_controller.dart';

/// The application's [AuthRepository] (SRS FR-001).
///
/// This is the dependency-injection seam for identity, and the only place the
/// Firebase implementation is chosen. When Firebase did not initialize — an
/// unconfigured build, or a failed start — the app uses
/// [UnavailableAuthRepository] instead of pretending accounts work (ADR-008).
///
/// Tests override this with a fake; the screens, the router guard and the
/// controllers never know which implementation is in play.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) {
    return const UnavailableAuthRepository();
  }
  return FirebaseAuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(loggerProvider),
  );
});

/// The application's [ProfileRepository] (SRS FR-002).
///
/// Selected with the same rule as [authRepositoryProvider], so a build can never
/// have one half configured. Tests override it with a fake.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) {
    return const UnavailableProfileRepository();
  }
  return FirestoreProfileRepository(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(loggerProvider),
  );
});

/// Orchestrates identity and profile writes (registration, sign-in, sign-out).
///
/// Kept as a provider so the multi-system registration flow is testable by
/// overriding the two repositories only.
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    auth: ref.watch(authRepositoryProvider),
    profiles: ref.watch(profileRepositoryProvider),
  ),
);

/// Whether an account service is reachable in this build.
///
/// Lets a screen state the truth ("accounts are unavailable here") instead of
/// offering a form that cannot succeed.
final authAvailableProvider = Provider<bool>(
  (ref) => ref.watch(authRepositoryProvider).isAvailable,
);

/// A user-safe explanation for [authAvailableProvider] being false.
final authUnavailableReasonProvider = Provider<String?>(
  (ref) => ref.watch(authRepositoryProvider).unavailableReason,
);

/// The current authentication state (SRS Task 2).
///
/// The router guard, the splash screen and the profile screen all observe this
/// one source of truth; no widget keeps a private copy of "am I signed in"
/// (ADR-006).
final authStateProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in identity, or `null`.
///
/// A convenience projection of [authStateProvider] so consumers do not have to
/// match on the sealed state when they only need the uid.
final currentIdentityProvider = Provider<AuthIdentity?>(
  (ref) => ref.watch(authStateProvider).identity,
);

/// The profile document for [uid] (SRS FR-002).
///
/// Keyed by uid on purpose: a different account reads a different provider
/// instance, so one user's profile can never be shown from another user's cache
/// after a sign-out or a switch (NFR-004).
///
/// `Success(null)` means the document does not exist — a state the UI must
/// represent explicitly rather than filling with invented data (FR-048).
final userProfileProvider = FutureProvider.family<Result<AppUser?>, String>(
  (ref, uid) => ref.watch(authServiceProvider).loadProfile(uid),
);

/// The signed-in user's profile.
///
/// Resolves to `Success(null)` when nobody is signed in, so callers can treat
/// "signed out" and "profile missing" as distinct states without null-checking
/// the identity first.
final currentUserProfileProvider = Provider<AsyncValue<Result<AppUser?>>>((
  ref,
) {
  final identity = ref.watch(currentIdentityProvider);
  if (identity == null) {
    return const AsyncData<Result<AppUser?>>(Success<AppUser?>(null));
  }
  return ref.watch(userProfileProvider(identity.uid));
});

/// The private settings document for [uid] (FR-022, FR-042).
final userPreferencesProvider =
    FutureProvider.family<Result<UserPreferences>, String>(
      (ref, uid) => ref.watch(profileRepositoryProvider).getPreferences(uid),
    );
