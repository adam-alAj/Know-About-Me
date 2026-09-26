import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/logging/app_logger.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/data/repositories/local_device_state_repository.dart';
import 'package:kam/features/device_state/data/services/app_device_identity.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/services/device_identity_store.dart';
import 'package:kam/features/device_state/domain/sources/device_state_provider.dart';
import 'package:kam/features/device_state/domain/sources/platform_device_state_adapter.dart';

void main() {
  final instant = DateTime.utc(2026, 9, 26, 12);

  test('snapshot round trips partial metrics and timestamps', () {
    final snapshot = DeviceStateSnapshot(
      deviceId: 'opaque',
      userId: 'user-a',
      collectedAt: instant,
      capabilities: {
        DeviceMetric.batteryPercentage: StateObservation<Object?>(
          availability: CapabilityAvailability.available,
          value: 72,
          observedAt: instant,
          updatedAt: instant,
          source: 'test',
          platform: 'android',
        ),
        DeviceMetric.location: const StateObservation<Object?>(
          availability: CapabilityAvailability.permissionDenied,
          permissionState: DevicePermissionState.denied,
        ),
      },
    );

    final restored = DeviceStateSnapshot.fromJson(snapshot.toJson());
    expect(restored.deviceId, 'opaque');
    expect(restored.collectedAt, instant);
    expect(restored[DeviceMetric.batteryPercentage]?.value, 72);
    expect(restored[DeviceMetric.location]?.availability,
        CapabilityAvailability.permissionDenied);
    expect(restored.capabilities, hasLength(2));
  });

  test('every explicit availability remains serializable', () {
    for (final availability in CapabilityAvailability.values) {
      final reading = StateObservation<Object?>(availability: availability);
      expect(StateObservation<Object?>.fromJson(reading.toJson()).availability,
          availability);
    }
  });

  test('snapshot observation exposes stale timestamps as stale', () {
    final old = StateObservation<Object?>(
      availability: CapabilityAvailability.available,
      value: 50,
      observedAt: instant.subtract(const Duration(hours: 1)),
    );
    expect(old.freshnessAt(instant), DataFreshness.stale);
  });

  test('one capability exception preserves sibling observations', () async {
    final provider = PlatformDeviceStateProvider(
      deviceId: () async => 'device',
      userId: () => 'user',
      adapter: _Adapter(),
      clock: () => instant,
      logger: const NoopAppLogger(),
    );
    final state = await provider.getCurrentState();
    expect(state[DeviceMetric.location]?.availability,
        CapabilityAvailability.error);
    expect(state[DeviceMetric.batteryPercentage]?.value, 80);
    expect(state[DeviceMetric.networkStatus]?.availability,
        CapabilityAvailability.available);
    expect(state.capabilities, hasLength(DeviceMetric.values.length));
  });

  test('repository caches current local state until refresh', () async {
    final provider = PlatformDeviceStateProvider(
      deviceId: () async => 'device',
      userId: () => 'user',
      adapter: _Adapter(),
      clock: () => instant,
      logger: const NoopAppLogger(),
    );
    final repository = LocalDeviceStateRepository(provider);
    final first = await repository.getCurrentLocalState();
    expect(await repository.getCurrentLocalState(), same(first));
    expect((await repository.refresh()).deviceId, 'device');
  });

  test('monitoring controller starts once and cancels on stop', () async {
    final provider = _CountingProvider();
    final controller = DeviceMonitoringController(LocalDeviceStateRepository(provider));
    final subscription = controller.snapshots.listen((_) {});
    await controller.startMonitoring();
    await controller.startMonitoring();
    expect(provider.starts, 1);
    await controller.stopMonitoring();
    expect(provider.cancellations, 1);
    await subscription.cancel();
    await controller.dispose();
  });

  test('identity is generated once, recovered if malformed, and persisted', () async {
    final store = _MemoryIdentityStore();
    var randomByte = 1;
    final identity = AppDeviceIdentity(store, random: _FakeRandom(() => randomByte++));
    final first = await identity.getOrCreate();
    expect(first, hasLength(32));
    expect(await identity.getOrCreate(), first);
    expect(store.writes, 1);

    store.value = 'malformed';
    final recovered = await identity.getOrCreate();
    expect(recovered, hasLength(32));
    expect(recovered, isNot(first));
    expect(store.writes, 2);
  });
}

class _Adapter implements PlatformDeviceStateAdapter {
  @override
  String get platformName => DevicePlatform.android.name;

  @override
  DeviceCapabilityStatus capabilityStatus(DeviceMetric capability) =>
      const DeviceCapabilityStatus(CapabilitySupport.unsupported);

  @override
  Future<StateObservation<Object?>> collect(DeviceMetric capability) async {
    if (capability == DeviceMetric.location) throw StateError('test');
    return StateObservation<Object?>(
      availability: CapabilityAvailability.available,
      value: capability == DeviceMetric.batteryPercentage ? 80 : null,
      observedAt: DateTime.utc(2026, 9, 26, 12),
    );
  }
}

class _MemoryIdentityStore implements DeviceIdentityStore {
  String? value;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async { this.value = value; writes++; }
  @override
  Future<void> remove() async { value = null; }
}

class _FakeRandom implements Random {
  _FakeRandom(this.next);
  final int Function() next;
  @override
  bool nextBool() => next() % 2 == 0;
  @override
  double nextDouble() => next() / 256;
  @override
  int nextInt(int max) => next() % max;
}

class _CountingProvider implements DeviceStateProvider {
  int starts = 0;
  int cancellations = 0;

  @override
  Map<DeviceMetric, DeviceCapabilityStatus> getCapabilityStatus() => const {};

  @override
  Future<DeviceStateSnapshot> getCurrentState() async => DeviceStateSnapshot(
    deviceId: 'device',
    userId: 'user',
    collectedAt: DateTime.utc(2026),
    capabilities: const {},
  );

  @override
  Stream<DeviceStateSnapshot> watchState() => Stream.multi((controller) {
    starts++;
    controller.onCancel = () {
      cancellations++;
    };
  });
}
