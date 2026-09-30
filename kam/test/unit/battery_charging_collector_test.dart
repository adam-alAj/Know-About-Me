import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/logging/app_logger.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/domain/models/battery_state.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/services/battery_charging_collector.dart';
import 'package:kam/features/device_state/domain/sources/battery_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/platform_device_state_adapter.dart';

void main() {
  final observedAt = DateTime.utc(2026, 9, 26, 12);

  for (final percentage in [0, 1, 50, 99, 100]) {
    test('accepts battery percentage $percentage', () async {
      final collector = BatteryChargingCollector(
        gateway: _FakeBatteryGateway(_sample(percentage: percentage)),
        now: () => observedAt,
      );
      final state = await collector.refresh();
      expect(state.percentage.value, percentage);
      expect(state.percentage.availability, CapabilityAvailability.available);
    });
  }

  test('null percentage is unavailable and invalid values are errors', () async {
    for (final value in [null, -1, 101, 20.5]) {
      final collector = BatteryChargingCollector(
        gateway: _FakeBatteryGateway(_sample(percentage: value)),
        now: () => observedAt,
      );
      final state = await collector.refresh();
      expect(
        state.percentage.availability,
        value == null
            ? CapabilityAvailability.unavailable
            : CapabilityAvailability.error,
      );
    }
  });

  test('initial charging reading has unknown start and duration', () async {
    final collector = BatteryChargingCollector(
      gateway: _FakeBatteryGateway(_sample(charging: 'charging')),
      now: () => observedAt,
    );
    final state = await collector.refresh();
    expect(state.chargingState.value, BatteryChargingState.charging);
    expect(state.chargingStartedAt, isNull);
    expect(state.chargingDuration.availability, CapabilityAvailability.unknown);
  });

  test('full remains distinct from a 100 percent reading', () async {
    final collector = BatteryChargingCollector(
      gateway: _FakeBatteryGateway(_sample(percentage: 100, charging: 'full')),
      now: () => observedAt,
    );
    final state = await collector.refresh();
    expect(state.percentage.value, 100);
    expect(state.chargingState.value, BatteryChargingState.full);
    expect(state.chargingStartedAt, isNull);
    expect(state.chargingDuration.availability, CapabilityAvailability.unknown);
  });

  test('stopping observation preserves an observed charging session', () async {
    // Regression (charging duration): monitoring is released whenever the app
    // is backgrounded. Discarding the session there was the reason the duration
    // was almost never shown. An observed start now survives the gap, and is
    // cleared only by a real non-charging observation.
    final gateway = _FakeBatteryGateway(_sample(charging: 'discharging'));
    final collector = BatteryChargingCollector(gateway: gateway, now: () => observedAt);
    await collector.refresh();
    gateway.current = _sample(charging: 'charging');
    await collector.refresh();
    await collector.stop();
    gateway.current = _sample(charging: 'charging');
    final resumed = await collector.refresh();
    expect(resumed.chargingStartedAt, observedAt);
    expect(resumed.chargingDuration.availability, CapabilityAvailability.available);
  });

  test('charging duration is derived from the observed start timestamp', () async {
    var now = observedAt;
    final gateway = _FakeBatteryGateway(_sample(charging: 'discharging'));
    final collector = BatteryChargingCollector(gateway: gateway, now: () => now);
    await collector.refresh();
    gateway.current = _sample(charging: 'charging');
    await collector.refresh();

    now = observedAt.add(const Duration(minutes: 95));
    final later = await collector.refresh();
    expect(later.chargingStartedAt, observedAt);
    expect(later.chargingDuration.value, const Duration(minutes: 95));
    expect(later.chargingDuration.availability, CapabilityAvailability.available);
  });

  test('observed transition establishes a start and session duration', () async {
    final gateway = _FakeBatteryGateway(_sample(charging: 'discharging'));
    final collector = BatteryChargingCollector(gateway: gateway, now: () => observedAt);
    await collector.refresh();

    gateway.current = _sample(charging: 'charging');
    final state = await collector.refresh();
    expect(state.chargingStartedAt, observedAt);
    expect(state.chargingDuration.availability, CapabilityAvailability.available);
    expect(state.chargingDuration.value, isNotNull);
  });

  test('unknown charging state clears the previous session', () async {
    final gateway = _FakeBatteryGateway(_sample(charging: 'discharging'));
    final collector = BatteryChargingCollector(gateway: gateway, now: () => observedAt);
    await collector.refresh();
    gateway.current = _sample(charging: 'charging');
    await collector.refresh();
    gateway.current = _sample(charging: 'unknown');
    final unknown = await collector.refresh();
    expect(unknown.chargingStartedAt, isNull);
    expect(unknown.chargingDuration.availability, CapabilityAvailability.unavailable);
  });

  test('charging to full preserves an observed session, then ends when unplugged', () async {
    final gateway = _FakeBatteryGateway(_sample(charging: 'discharging'));
    final collector = BatteryChargingCollector(gateway: gateway, now: () => observedAt);
    await collector.refresh();
    gateway.current = _sample(charging: 'charging');
    final charging = await collector.refresh();
    expect(charging.chargingStartedAt, observedAt);

    gateway.current = _sample(charging: 'full');
    final full = await collector.refresh();
    expect(full.chargingStartedAt, observedAt);
    expect(full.chargingDuration.availability, CapabilityAvailability.available);

    gateway.current = _sample(charging: 'discharging');
    final ended = await collector.refresh();
    expect(ended.chargingStartedAt, isNull);
    expect(ended.chargingDuration.availability, CapabilityAvailability.unavailable);
  });

  test('missing percentage does not invalidate a reported charging state', () async {
    final collector = BatteryChargingCollector(
      gateway: _FakeBatteryGateway(_sample(percentage: null, charging: 'charging')),
      now: () => observedAt,
    );
    final state = await collector.refresh();
    expect(state.percentage.availability, CapabilityAvailability.unavailable);
    expect(state.chargingState.value, BatteryChargingState.charging);
  });

  test('battery observations become stale by their timestamps', () async {
    final state = await BatteryChargingCollector(
      gateway: _FakeBatteryGateway(_sample()),
      now: () => observedAt,
    ).refresh();
    expect(state.freshnessAt(observedAt), DataFreshness.fresh);
    expect(
      state.freshnessAt(observedAt.add(const Duration(minutes: 16))),
      DataFreshness.stale,
    );
  });

  test('battery failure does not prevent unrelated device metrics', () async {
    final gateway = _FakeBatteryGateway(_sample())..readError = StateError('test');
    final batteryCollector = BatteryChargingCollector(
      gateway: gateway,
      now: () => observedAt,
    );
    final provider = PlatformDeviceStateProvider(
      deviceId: () async => 'device',
      userId: () => 'user',
      adapter: _UnrelatedMetricAdapter(),
      clock: () => observedAt,
      logger: const NoopAppLogger(),
      batteryCollector: batteryCollector,
    );

    final snapshot = await provider.getCurrentState();
    expect(snapshot.battery?.percentage.availability, CapabilityAvailability.error);
    expect(snapshot[DeviceMetric.networkStatus]?.value, 'online');
  });

  test('non-Android battery collection is unsupported and state round-trips', () async {
    final collector = BatteryChargingCollector(
      gateway: _FakeBatteryGateway(
        _sample(charging: 'full', sourceSupported: false),
        platformName: 'nonAndroid',
      ),
      now: () => observedAt,
    );
    final state = await collector.refresh();
    expect(state.percentage.availability, CapabilityAvailability.unsupported);
    expect(state.chargingState.availability, CapabilityAvailability.unsupported);
    expect(state.chargingDuration.availability, CapabilityAvailability.unsupported);
    expect(state.chargingSource.availability, CapabilityAvailability.unsupported);
    final restored = BatteryState.fromJson(state.toJson());
    expect(restored.percentage.value, state.percentage.value);
    expect(restored.chargingState.availability, CapabilityAvailability.unsupported);
    expect(restored.chargingSource.availability, CapabilityAvailability.unsupported);

    final snapshot = DeviceStateSnapshot(
      deviceId: 'device',
      userId: 'owner',
      collectedAt: observedAt,
      capabilities: const {},
      battery: state,
    );
    final restoredSnapshot = DeviceStateSnapshot.fromJson(snapshot.toJson());
    expect(
      restoredSnapshot.battery?.chargingState.availability,
      CapabilityAvailability.unsupported,
    );
    expect(restoredSnapshot.battery?.chargingState.value, isNull);
  });
}

BatteryPlatformSample _sample({
  Object? percentage = 76,
  String charging = 'discharging',
  String? source = 'unknown',
  bool sourceSupported = true,
}) => BatteryPlatformSample(
  percentage: percentage,
  chargingState: charging,
  chargingSource: source,
  chargingSourceSupported: sourceSupported,
);

class _FakeBatteryGateway implements BatteryPlatformGateway {
  _FakeBatteryGateway(this.current, {this.platformName = 'android'});
  Object? current;
  Object? readError;
  @override
  final String platformName;
  final _events = StreamController<Object?>.broadcast();

  @override
  Future<Object?> readCurrent() async {
    final error = readError;
    if (error != null) throw error;
    return current;
  }

  @override
  Stream<Object?> watchChanges() => _events.stream;

  void emit(Object? value) {
    current = value;
    _events.add(value);
  }
}

class _UnrelatedMetricAdapter implements PlatformDeviceStateAdapter {
  @override
  String get platformName => DevicePlatform.android.name;

  @override
  DeviceCapabilityStatus capabilityStatus(DeviceMetric capability) =>
      const DeviceCapabilityStatus(CapabilitySupport.unsupported);

  @override
  Future<StateObservation<Object?>> collect(DeviceMetric capability) async =>
      StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: capability == DeviceMetric.networkStatus ? 'online' : null,
        observedAt: DateTime.utc(2026, 9, 26, 12),
      );
}
