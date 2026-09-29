import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_exception.dart';
import 'package:kam/core/error/app_failure.dart';

void main() {
  group('AppFailure.fromException', () {
    test('maps each AppException subtype to its failure kind', () {
      expect(
        AppFailure.fromException(const ConfigurationException('bad env')).type,
        FailureType.configuration,
      );
      expect(
        AppFailure.fromException(
          const RemoteServiceException('backend down'),
        ).type,
        FailureType.remoteService,
      );
      expect(
        AppFailure.fromException(const PermissionException('denied')).type,
        FailureType.permission,
      );
      expect(
        AppFailure.fromException(
          const UnsupportedCapabilityException(
            'Screen state is unsupported on this target.',
          ),
        ).type,
        FailureType.unsupportedCapability,
      );
    });

    test('keeps an underlying cause for logging', () {
      final failure = AppFailure.fromException(
        const RemoteServiceException('timeout', cause: 'timeout-detail'),
      );

      expect(failure.cause, 'timeout-detail');
    });

    test('passes an existing AppFailure through unchanged', () {
      const original = ValidationFailure('Threshold must be positive');

      expect(AppFailure.fromException(original), same(original));
    });

    test('never exposes internals for unknown errors', () {
      final failure = AppFailure.fromException(
        Exception('SQLSTATE 42P01 secret table name'),
      );

      expect(failure.type, FailureType.unexpected);
      expect(failure.message, isNot(contains('secret')));
      // The real error is still retained for logging.
      expect(failure.cause, isNotNull);
    });
  });
}
