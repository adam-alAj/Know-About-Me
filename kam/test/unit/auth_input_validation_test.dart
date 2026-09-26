import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';
import 'package:kam/features/auth/domain/validation/auth_input_validation.dart';

void main() {
  group('email', () {
    test('accepts an ordinary address', () {
      expect(AuthInputValidation.email('afraa@example.com'), isNull);
    });

    test('accepts surrounding whitespace', () {
      expect(AuthInputValidation.email('  afraa@example.com  '), isNull);
    });

    test('rejects an empty value', () {
      expect(AuthInputValidation.email(''), isNotNull);
      expect(AuthInputValidation.email(null), isNotNull);
    });

    test('rejects a value without an @ or a domain dot', () {
      expect(AuthInputValidation.email('afraa'), isNotNull);
      expect(AuthInputValidation.email('afraa@example'), isNotNull);
      expect(AuthInputValidation.email('a b@example.com'), isNotNull);
    });

    test('does not echo the rejected value', () {
      // A message must never repeat input back: it could place a credential in
      // a log or a UI string.
      expect(
        AuthInputValidation.email('secret-value'),
        isNot(contains('secret-value')),
      );
    });
  });

  group('password', () {
    test('accepts a password at the minimum length', () {
      final ok = 'a' * AuthInputValidation.minimumPasswordLength;
      expect(AuthInputValidation.password(ok), isNull);
    });

    test('rejects an empty or too-short password', () {
      expect(AuthInputValidation.password(''), isNotNull);
      expect(AuthInputValidation.password('short'), isNotNull);
    });

    test('does not echo the password', () {
      expect(
        AuthInputValidation.password('hunter2'),
        isNot(contains('hunter2')),
      );
    });
  });

  group('confirmPassword', () {
    test('accepts a matching value', () {
      expect(
        AuthInputValidation.confirmPassword('password1', password: 'password1'),
        isNull,
      );
    });

    test('rejects a mismatch and an empty value', () {
      expect(
        AuthInputValidation.confirmPassword('password2', password: 'password1'),
        isNotNull,
      );
      expect(
        AuthInputValidation.confirmPassword('', password: 'password1'),
        isNotNull,
      );
    });
  });

  group('displayName', () {
    test('accepts a normal name and trims whitespace', () {
      expect(AuthInputValidation.displayName('Afraa'), isNull);
      expect(AuthInputValidation.displayName('  Afraa  '), isNull);
    });

    test('rejects empty and whitespace-only names', () {
      expect(AuthInputValidation.displayName(''), isNotNull);
      expect(AuthInputValidation.displayName('   '), isNotNull);
      expect(AuthInputValidation.displayName(null), isNotNull);
    });

    test('accepts the maximum length and rejects one character more', () {
      final max = 'a' * AppUser.maxDisplayNameLength;
      expect(AuthInputValidation.displayName(max), isNull);
      expect(AuthInputValidation.displayName('${max}a'), isNotNull);
    });

    test('keeps the client bound equal to the Security Rules bound', () {
      // firebase/firestore.rules requires size() <= 120 for displayName.
      expect(
        AuthInputValidation.maximumDisplayNameLength,
        AppUser.maxDisplayNameLength,
      );
    });
  });

  group('firstFailure', () {
    test('returns the first message and skips the later ones', () {
      final failure = AuthInputValidation.firstFailure([
        null,
        'Second problem',
        'Third problem',
      ]);

      expect(failure, isA<ValidationFailure>());
      expect(failure!.message, 'Second problem');
    });

    test('returns null when everything passes', () {
      expect(AuthInputValidation.firstFailure([null, null]), isNull);
    });
  });
}
