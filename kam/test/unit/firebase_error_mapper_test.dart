// firebase_auth re-exports `FirebaseException` from firebase_core.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/firebase/firebase_error_mapper.dart';

void main() {
  FirebaseException firestore(String code, [String? message]) =>
      FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
        message: message,
      );

  FirebaseAuthException auth(String code, [String? message]) =>
      FirebaseAuthException(code: code, message: message);

  group('Firestore codes map to classified failures', () {
    test('permission-denied becomes a permission failure', () {
      final failure = FirebaseErrorMapper.toFailure(
        firestore('permission-denied', 'Missing or insufficient permissions.'),
      );

      expect(failure, isA<PermissionFailure>());
      expect(failure.type, FailureType.permission);
    });

    test('unauthenticated becomes an authentication failure', () {
      expect(
        FirebaseErrorMapper.toFailure(firestore('unauthenticated')),
        isA<AuthenticationFailure>(),
      );
    });

    test('not-found becomes a not-found failure', () {
      expect(
        FirebaseErrorMapper.toFailure(firestore('not-found')),
        isA<NotFoundFailure>(),
      );
    });

    test('unavailable and deadline-exceeded become remote failures', () {
      expect(
        FirebaseErrorMapper.toFailure(firestore('unavailable')),
        isA<RemoteServiceFailure>(),
      );
      expect(
        FirebaseErrorMapper.toFailure(firestore('deadline-exceeded')),
        isA<RemoteServiceFailure>(),
      );
    });

    test('failed-precondition becomes a validation failure', () {
      expect(
        FirebaseErrorMapper.toFailure(firestore('failed-precondition')),
        isA<ValidationFailure>(),
      );
    });

    test(
      'an unrecognised code still becomes a remote failure, not a crash',
      () {
        final failure = FirebaseErrorMapper.toFailure(
          firestore('some-future-code', 'details'),
        );

        expect(failure, isA<RemoteServiceFailure>());
      },
    );
  });

  group('Auth codes map to classified failures', () {
    test('account enumeration is not possible from the message', () {
      final wrongPassword = FirebaseErrorMapper.toFailure(
        auth('wrong-password', 'The password is invalid.'),
      );
      final userNotFound = FirebaseErrorMapper.toFailure(
        auth('user-not-found', 'There is no user record.'),
      );
      final invalidCredential = FirebaseErrorMapper.toFailure(
        auth('invalid-credential', 'Invalid credential.'),
      );

      // Identical, deliberately vague message for all three.
      expect(wrongPassword.message, userNotFound.message);
      expect(userNotFound.message, invalidCredential.message);
      expect(wrongPassword, isA<AuthenticationFailure>());
    });

    test('validation errors are reported as validation failures', () {
      expect(
        FirebaseErrorMapper.toFailure(auth('email-already-in-use')),
        isA<ValidationFailure>(),
      );
      expect(
        FirebaseErrorMapper.toFailure(auth('invalid-email')),
        isA<ValidationFailure>(),
      );
      expect(
        FirebaseErrorMapper.toFailure(auth('weak-password')),
        isA<ValidationFailure>(),
      );
    });

    test('rate limiting is a remote failure, not a validation failure', () {
      expect(
        FirebaseErrorMapper.toFailure(auth('too-many-requests')),
        isA<RemoteServiceFailure>(),
      );
    });

    test('a disabled sign-in method is a configuration failure', () {
      expect(
        FirebaseErrorMapper.toFailure(auth('operation-not-allowed')),
        isA<ConfigurationFailure>(),
      );
    });

    test('missing Firebase Auth setup has an actionable safe message', () {
      final failure = FirebaseErrorMapper.toFailure(
        auth(
          'internal-error',
          'An internal error has occurred. [ CONFIGURATION_NOT_FOUND ]',
        ),
      );

      expect(failure, isA<ConfigurationFailure>());
      expect(failure.message, contains('Enable Firebase Authentication'));
      expect(failure.message, isNot(contains('CONFIGURATION_NOT_FOUND')));
    });
  });

  group('Sanitisation', () {
    test('raw SDK messages are never exposed to the user', () {
      final failure = FirebaseErrorMapper.toFailure(
        firestore('permission-denied', 'SQLSTATE 42P01 internal table name'),
      );

      expect(failure.message, isNot(contains('SQLSTATE')));
      // But the detail is kept for logging.
      expect(failure.cause, contains('SQLSTATE'));
    });

    test('a non-Firebase error falls back to generic classification', () {
      final failure = FirebaseErrorMapper.toFailure(
        StateError('internal implementation detail'),
      );

      expect(failure, isA<UnexpectedFailure>());
      expect(failure.message, isNot(contains('internal')));
    });

    test('every mapped message is non-empty and safe', () {
      const codes = <String>[
        'permission-denied',
        'unauthenticated',
        'not-found',
        'unavailable',
        'deadline-exceeded',
        'resource-exhausted',
        'failed-precondition',
        'cancelled',
        'invalid-argument',
        'internal',
        'unknown',
      ];

      for (final code in codes) {
        final failure = FirebaseErrorMapper.toFailure(firestore(code, code));
        expect(failure.message, isNotEmpty, reason: 'code $code');
        expect(failure.message, isNot(equals(code)), reason: 'code $code');
      }
    });
  });
}
