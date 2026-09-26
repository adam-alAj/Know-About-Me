import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/firebase/firebase_error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../domain/models/auth_identity.dart';
import '../../domain/repositories/auth_repository.dart';

/// [AuthRepository] backed by Firebase Authentication (SRS FR-001).
///
/// This class is the **only** place in the application that touches
/// `FirebaseAuth`. Everything above it sees [AuthIdentity] and [Result]
/// (constraint 4), and `test/architecture/domain_purity_test.dart` enforces that
/// SDK imports stay inside `core/firebase/` and `features/*/data/` (ADR-007).
///
/// Security notes:
///
/// - Credentials are passed straight to the SDK and never retained, logged or
///   stored. Log context carries the operation name only (NFR-045,
///   constraint 7).
/// - SDK failures are classified by [FirebaseErrorMapper], so a raw Firebase
///   message never reaches a user and authentication errors stay deliberately
///   vague to avoid account enumeration (constraint 10).
///
/// It is constructed only when Firebase initialized successfully (see
/// `authRepositoryProvider`), which is what makes [isAvailable] true.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._logger);

  final FirebaseAuth _auth;
  final AppLogger _logger;

  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;

  @override
  Stream<AuthIdentity?> watchIdentity() async* {
    try {
      await for (final user in _auth.authStateChanges()) {
        yield _toIdentity(user);
      }
    } catch (error, stackTrace) {
      // Emit a classified failure instead of silently reporting "signed out",
      // so the application can represent an unknown authentication state
      // rather than claiming the user is not signed in (SRS Task 21).
      _logger.error(
        'Authentication state stream failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw FirebaseErrorMapper.toFailure(error, stackTrace);
    }
  }

  @override
  Future<Result<AuthIdentity?>> currentIdentity() =>
      _guarded('currentIdentity', () async => _toIdentity(_auth.currentUser));

  @override
  Future<Result<AuthIdentity>> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _guarded('registerWithEmail', () async {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        // Defensive: the SDK contract says a successful call returns a user.
        throw StateError('Firebase returned no user for a successful sign-up');
      }
      return _identityOf(user);
    });
  }

  @override
  Future<Result<AuthIdentity>> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _guarded('signInWithEmail', () async {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw StateError('Firebase returned no user for a successful sign-in');
      }
      return _identityOf(user);
    });
  }

  @override
  Future<Result<void>> signOut() async {
    // Signs out of the provider only. The account and its profile are untouched
    // (SRS Task 7: logout is not account deletion).
    try {
      await _auth.signOut();
      return const Success<void>(null);
    } catch (error, stackTrace) {
      final failure = FirebaseErrorMapper.toFailure(error, stackTrace);
      _logger.warning(
        'Authentication operation failed',
        context: {'operation': 'signOut', 'failureType': failure.type.name},
      );
      return Failure<void>(failure);
    }
  }

  /// Runs [action], converting any thrown error into a classified failure.
  ///
  /// `Result.guard` is deliberately not used: it falls back to
  /// `AppFailure.fromException`, which would not understand Firebase error codes
  /// and would hide the specific messages the mapper produces.
  Future<Result<T>> _guarded<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return Success<T>(await action());
    } catch (error, stackTrace) {
      final failure = FirebaseErrorMapper.toFailure(error, stackTrace);
      // The operation name and failure category are safe to log; credentials,
      // tokens and email addresses are not.
      _logger.warning(
        'Authentication operation failed',
        context: {'operation': operation, 'failureType': failure.type.name},
      );
      return Failure<T>(failure);
    }
  }

  static AuthIdentity? _toIdentity(User? user) =>
      user == null ? null : _identityOf(user);

  static AuthIdentity _identityOf(User user) => AuthIdentity(
    uid: user.uid,
    email: user.email,
    emailVerified: user.emailVerified,
  );
}
