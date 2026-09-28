import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/history/domain/models/device_event.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 1, 2, 3, 4);

  test('serializes normalized event fields in UTC and restores them', () {
    final event = DeviceEvent(
      id: 'opaque', pairId: 'pair', ownerUserId: 'owner',
      type: DeviceEventType.chargingStarted,
      occurredAt: DateTime.utc(2026, 1, 2, 3, 4),
      observedAt: DateTime.utc(2026, 1, 2, 3, 3),
      source: 'device', deduplicationKey: 'opaque-key',
      summary: 'Charging started',
      payload: <String, Object?>{'transition': 'notCharging_to_charging'},
    );
    final restored = DeviceEvent.fromJson(event.toJson());
    expect(restored.type, DeviceEventType.chargingStarted);
    expect(restored.category, EventCategory.charging);
    expect(restored.occurredAt, occurredAt);
    expect(restored.observedAt, DateTime.utc(2026, 1, 2, 3, 3));
    expect(restored.ownerUserId, 'owner');
    expect(restored.payload['transition'], 'notCharging_to_charging');
  });

  test('rejects mismatched event taxonomy', () {
    expect(
      () => DeviceEvent.fromJson(<String, Object?>{
        'id': 'opaque', 'pairId': 'pair', 'type': 'chargingStarted',
        'category': 'network', 'occurredAt': occurredAt.toIso8601String(),
      }),
      throwsFormatException,
    );
  });

  test('categorizes rule and notification decisions separately', () {
    expect(DeviceEventType.ruleActivated.category, EventCategory.rules);
    expect(DeviceEventType.interpretationGenerated.category, EventCategory.rules);
    expect(DeviceEventType.ruleNotificationGenerated.category, EventCategory.notifications);
    expect(DeviceEventType.notificationSuppressed.category, EventCategory.notifications);
  });
}
