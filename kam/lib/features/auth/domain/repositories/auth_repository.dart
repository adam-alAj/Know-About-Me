import '../../../../core/result/result.dart';
import '../models/auth_identity.dart';

/// Contract for **identity** operations (SRS FR-001).
///
/// Firebase Authentication implements this (`FirebaseAuthRepository`). Nothing
/// above the data layer depends on the SDK (constraint 4), so routing, screens
/// and tests are written against this interface only.
///
/// Two invariants every implementation must honour:
///
/// - return [Result] rather than throwing (ADR-005), and
/// - report "nobody is signed in" as `null`, never as a synthesised identity.
abstract interface class AuthRepository {
  /// Whether an account service is reachable in this build.
  ///
  /// `false` when the app has no Firebase configuration, or when Firebase failed
  /// to initialize. The UI uses this to state the truth instead of offering a
  /// form that cannot succeed (SRS constraint 10: no fabricated availability).
  bool get isAvailable;

  /// A user-safe explanation of why accounts are unavailable.
  ///
  /// `null` when [isAvailable] is true. Never contains configuration internals
  /// or credentials — only a plain statement of the situation.
  String? get unavailableReason;

  /// Emits the signed-in identity, or `null` when signed out.
  ///
  /// Errors are emitted on the stream when the provider becomes unreachable, so
  /// the application can represent "authentication state unknown" instead of
  /// silently pretending the user is signed out.
  Stream<AuthIdentity?> watchIdentity();

  /// Reads the current identity once.
  Future<Result<AuthIdentity?>> currentIdentity();

  /// Creates an account and returns its identity.
  Future<Result<AuthIdentity>> registerWithEmail({
    required String email,
    required String password,
  });

  /// Authenticates an existing account.
  Future<Result<AuthIdentity>> signInWithEmail({
    required String email,
    required String password,
  });

  /// Ends the session.
  ///
  /// Signs out of the provider only. It never deletes the account or the user's
  /// profile document (SRS Task 7).
  Future<Result<void>> signOut();
}
