// `FirebaseException` (firebase_core) is re-exported by firebase_auth, so a
// separate firebase_core import would be redundant here.
import 'package:firebase_auth/firebase_auth.dart';

import '../error/app_failure.dart';

/// Maps Firebase exceptions onto the application's failure vocabulary.
///
/// SRS Task 22: Firebase failures are converted into classified
/// [AppFailure]s, raw SDK messages are never shown to a user, and nothing is
/// swallowed. Codes follow the official Firestore and Auth error documentation.
///
/// Rules applied here:
///
/// - the user gets a safe, actionable message,
/// - the original error is retained in `cause` for logging,
/// - authentication errors are deliberately vague about *why* credentials were
///   rejected, so the app does not help an attacker enumerate accounts.
abstract final class FirebaseErrorMapper {
  /// Classifies [error], falling back to `AppFailure.fromException`.
  static AppFailure toFailure(Object error, [StackTrace? stackTrace]) {
    if (error is FirebaseAuthException) {
      return _fromAuth(error, stackTrace);
    }
    if (error is FirebaseException) {
      return _fromFirestore(error, stackTrace);
    }
    return AppFailure.fromException(error, stackTrace);
  }

  static AppFailure _fromFirestore(
    FirebaseException error,
    StackTrace? stackTrace,
  ) {
    final detail = error.message ?? error.code;

    switch (error.code) {
      case 'permission-denied':
        return AuthorizationFailure(
          'This action is no longer authorized. Your connection or sharing permissions may have changed.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'unauthenticated':
        return AuthenticationFailure(
          'Your session has expired. Please sign in again.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'not-found':
        return NotFoundFailure(
          'That information is no longer available.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'unavailable':
      case 'network-request-failed':
      case 'retry-limit-exceeded':
        return RemoteServiceFailure(
          'Could not reach the service. Check your connection and try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'deadline-exceeded':
        return RemoteServiceFailure(
          'The request took too long. Please try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'resource-exhausted':
        return RemoteServiceFailure(
          'The service is busy right now. Please try again shortly.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'failed-precondition':
        return ValidationFailure(
          'That action is not allowed in the current state.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'cancelled':
        return RemoteServiceFailure(
          'The request was cancelled.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'already-exists':
        return ValidationFailure(
          'That already exists.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'invalid-argument':
        return ValidationFailure(
          'That request contained invalid information.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'unimplemented':
      case 'internal':
      case 'unknown':
        return RemoteServiceFailure(
          'Something went wrong on the service. Please try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
      default:
        // Unknown Firestore code: classify as remote rather than "unexpected",
        // because the call did reach Firebase.
        return RemoteServiceFailure(
          'Could not complete the request. Please try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
    }
  }

  static AppFailure _fromAuth(
    FirebaseAuthException error,
    StackTrace? stackTrace,
  ) {
    final detail = error.message ?? error.code;

    // Android can surface a missing Firebase Authentication project/provider
    // configuration as a generic internal-error with this backend marker.
    // Give the developer/user the one actionable setup step without exposing
    // the raw backend message.
    if (detail.contains('CONFIGURATION_NOT_FOUND')) {
      return ConfigurationFailure(
        'Account creation is not configured for this Firebase project. '
        'Enable Firebase Authentication and Email/Password sign-in in the '
        'Firebase Console.',
        cause: detail,
        stackTrace: stackTrace,
      );
    }

    switch (error.code) {
      // Deliberately combined: revealing which of these applies would leak
      // whether an account exists (account enumeration).
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return AuthenticationFailure(
          'The email or password is incorrect.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'user-disabled':
        return AuthenticationFailure(
          'This account is not available. Please contact support.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'requires-recent-login':
        return AuthenticationFailure(
          'Please sign in again to continue.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'user-mismatch':
        return AuthenticationFailure(
          'This account does not match the signed-in user.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'email-already-in-use':
        return ValidationFailure(
          'That email address is already registered.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'invalid-email':
        return ValidationFailure(
          'Please enter a valid email address.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'weak-password':
        return ValidationFailure(
          'Please choose a stronger password.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'missing-password':
        return ValidationFailure(
          'Please enter your password.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'operation-not-allowed':
        return ConfigurationFailure(
          'That sign-in method is not enabled.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'too-many-requests':
        return RemoteServiceFailure(
          'Too many attempts. Please wait and try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
      case 'network-request-failed':
        return RemoteServiceFailure(
          'Could not reach the service. Check your connection and try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
      default:
        return AuthenticationFailure(
          'Could not complete sign-in. Please try again.',
          cause: detail,
          stackTrace: stackTrace,
        );
    }
  }
}
