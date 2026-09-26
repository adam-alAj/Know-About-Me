import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_exception.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';

void main() {
  group('Result', () {
    test('success exposes its value', () {
      const result = Success<int>(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('failure exposes its failure', () {
      const result = Failure<int>(PermissionFailure('No access to location'));

      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull?.type, FailureType.permission);
    });

    test('fold maps both branches', () {
      expect(
        const Success<int>(
          2,
        ).fold(onSuccess: (v) => 'ok $v', onFailure: (f) => 'bad'),
        'ok 2',
      );
      expect(
        const Failure<int>(
          UnexpectedFailure('boom'),
        ).fold(onSuccess: (v) => 'ok', onFailure: (f) => 'bad'),
        'bad',
      );
    });

    test('map transforms a success and passes a failure through', () {
      expect(const Success<int>(2).map((v) => v * 3).valueOrNull, 6);

      final mapped = const Failure<int>(
        UnexpectedFailure('boom'),
      ).map((v) => v * 3);
      expect(mapped.isFailure, isTrue);
    });
  });

  group('Result.guard', () {
    test('wraps a successful async action', () async {
      final result = await Result.guard(() async => 'value');

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, 'value');
    });

    test('converts a thrown AppException into a classified failure', () async {
      final result = await Result.guard<void>(
        () async =>
            throw const PermissionException('Location permission denied'),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<PermissionFailure>());
      expect(result.failureOrNull?.message, 'Location permission denied');
    });

    test('converts an unexpected error into a safe, generic failure', () async {
      final result = await Result.guard<void>(
        () async => throw StateError('internal detail'),
      );

      expect(result.failureOrNull, isA<UnexpectedFailure>());
      // Internals are not leaked to the user.
      expect(result.failureOrNull?.message, isNot(contains('internal detail')));
    });

    test('guardSync behaves the same way', () {
      final ok = Result.guardSync(() => 1);
      final bad = Result.guardSync<int>(() => throw StateError('x'));

      expect(ok.valueOrNull, 1);
      expect(bad.isFailure, isTrue);
    });
  });
}
