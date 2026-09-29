import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kam/features/history/data/shared_preferences_history_repository.dart';
import 'package:kam/features/history/domain/models/device_event.dart';

/// Phase 19: the offline history cache is device-wide, so reads must be scoped
/// by owner. Without this, one account's cached timeline would be rendered to a
/// different account that signs in on the same device (SRS NFR-004).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesHistoryRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = SharedPreferencesHistoryRepository(
      now: () => DateTime.utc(2026, 1, 2),
    );
  });

  DeviceEvent event(String id, String ownerUserId) => DeviceEvent(
    id: id,
    pairId: 'p1',
    ownerUserId: ownerUserId,
    type: DeviceEventType.deviceWentOffline,
    occurredAt: DateTime.utc(2026, 1, 1),
    source: 'device',
    summary: 'Connectivity unavailable',
  );

  test('page returns only the requested owner\'s events', () async {
    await repository.add(event('a1', 'user-a'));
    await repository.add(event('a2', 'user-a'));
    await repository.add(event('b1', 'user-b'));

    final forA = await repository.page(ownerUserId: 'user-a', limit: 100);
    final forB = await repository.page(ownerUserId: 'user-b', limit: 100);

    expect(forA.map((item) => item.id).toList()..sort(), <String>['a1', 'a2']);
    expect(forB.map((item) => item.id).toList(), <String>['b1']);
  });

  test('an unknown owner sees nothing rather than everything', () async {
    await repository.add(event('a1', 'user-a'));

    final forStranger = await repository.page(
      ownerUserId: 'user-c',
      limit: 100,
    );

    expect(forStranger, isEmpty);
  });

  test('a retried event is stored exactly once', () async {
    // Phase 20 §14: a network failure that is retried must not turn one
    // "charging started" into three. The id is the idempotency key, so a retry
    // of the same event is a no-op rather than a second entry.
    final retried = event('charging-1', 'user-a');
    await repository.add(retried);
    await repository.add(retried);
    await repository.add(retried);

    final events = await repository.page(ownerUserId: 'user-a', limit: 100);

    expect(events.map((item) => item.id).toList(), <String>['charging-1']);
  });

  test('an owner filter composes with the category filter', () async {
    await repository.add(event('a1', 'user-a'));
    await repository.add(
      DeviceEvent(
        id: 'a2',
        pairId: 'p1',
        ownerUserId: 'user-a',
        type: DeviceEventType.chargingStarted,
        occurredAt: DateTime.utc(2026, 1, 1),
        source: 'device',
      ),
    );

    final charging = await repository.page(
      category: EventCategory.charging,
      ownerUserId: 'user-a',
      limit: 100,
    );

    expect(charging.map((item) => item.id).toList(), <String>['a2']);
  });
}
