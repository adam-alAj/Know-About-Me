import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/notifications/local_notification_service.dart';

/// Tests of the local-notification abstraction.
///
/// No production notification plugin is involved: the default implementation is
/// exercised directly, so these tests prove the *contract* (an unsupported host
/// never claims to have delivered anything) without depending on an OS
/// notification service.
void main() {
  const request = LocalNotificationRequest(
    id: 'r1@2026-09-26T12:00:00.000Z',
    title: 'Possible sleep',
    body: 'There is a 70% possibility that Afraa is sleeping now.',
  );

  group('UnavailableLocalNotificationService', () {
    const service = UnavailableLocalNotificationService();

    test('reports honestly that it cannot present notifications', () {
      expect(service.isSupported, isFalse);
    });

    test(
      'a delivery attempt fails with an unsupported-capability failure',
      () async {
        final result = await service.show(request);

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<UnsupportedCapabilityFailure>());
        expect(result.failureOrNull!.type, FailureType.unsupportedCapability);
      },
    );

    test(
      'the failure message is user-safe and says the record is kept',
      () async {
        final result = await service.show(request);

        expect(result.failureOrNull!.message, contains('notification history'));
        // The message must not leak plugin or platform internals.
        expect(result.failureOrNull!.message, isNot(contains('Exception')));
      },
    );

    test('clearing notifications is a harmless no-op', () async {
      final result = await service.cancelAll();

      expect(result.isSuccess, isTrue);
    });

    test('permission operations report unsupported without prompting', () async {
      expect((await service.permissionState()).valueOrNull,
          NotificationPermissionState.unsupported);
      expect((await service.requestPermission()).valueOrNull,
          NotificationPermissionState.unsupported);
    });
  });

  group('LocalNotificationRequest', () {
    test('carries the identifiers a platform binding needs', () {
      expect(request.id, isNotEmpty);
      expect(request.title, isNotEmpty);
      expect(request.body, isNotEmpty);
      // No payload is required for a local notification.
      expect(request.payload, isNull);
    });
  });
}
