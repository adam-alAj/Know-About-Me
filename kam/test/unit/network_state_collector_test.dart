import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/logging/app_logger.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/models/network_state.dart';
import 'package:kam/features/device_state/domain/services/battery_charging_collector.dart';
import 'package:kam/features/device_state/domain/services/network_observation_store.dart';
import 'package:kam/features/device_state/domain/services/network_state_collector.dart';
import 'package:kam/features/device_state/domain/sources/battery_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/network_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/platform_device_state_adapter.dart';

void main() {
  final start = DateTime.utc(2026, 9, 26, 12);

  for (final type in [
    'wifi',
    'mobile',
    'ethernet',
    'bluetooth',
    'vpn',
    'none',
  ]) {
    test('normalizes connectivity type $type', () async {
      final collector = _collector(_sample(type: type), now: () => start);
      final state = await collector.refresh();
      expect(state.connectivity.value?.name, type);
      expect(state.connectivity.availability, CapabilityAvailability.available);
    });
  }

  test('unknown connectivity remains unknown', () async {
    final state = await _collector(
      _sample(type: 'unknown', status: 'unknown', internet: 'unknown'),
      now: () => start,
    ).refresh();
    expect(state.connectivity.value, ConnectivityType.unknown);
    expect(state.connectivity.availability, CapabilityAvailability.unknown);
    expect(state.status.value, NetworkOnlineStatus.unknown);
  });

  test('Wi-Fi transport with no validated Internet remains distinct and offline', () async {
    final state = await _collector(
      _sample(internet: 'unavailable', status: 'offline'),
      now: () => start,
    ).refresh();
    expect(state.connectivity.value, ConnectivityType.wifi);
    expect(state.internet.value, InternetReachability.unavailable);
    expect(state.status.value, NetworkOnlineStatus.offline);
  });

  test('unsupported platforms remain explicitly unsupported', () async {
    final collector = _collector(_sample(), platform: 'unknown', now: () => start);
    final state = await collector.refresh();
    expect(state.status.availability, CapabilityAvailability.unsupported);
    expect(
      collector.capabilityStatus[DeviceMetric.networkConnectivity]?.support,
      CapabilitySupport.unsupported,
    );
  });

  test('event monitoring starts once, emits transitions, and cancels cleanly', () async {
    final gateway = _FakeGateway(_sample());
    final collector = _collector(_sample(), gateway: gateway, now: () => start);
    await collector.start();
    await collector.start();
    expect(collector.isStarted, isTrue);
    expect(gateway._events.hasListener, isTrue);

    gateway.emit(_sample(type: 'none', status: 'offline', internet: 'unavailable'));
    await Future<void>.delayed(Duration.zero);
    expect(collector.current.status.value, NetworkOnlineStatus.offline);
    await collector.stop();
    expect(collector.isStarted, isFalse);
    expect(gateway._events.hasListener, isFalse);
  });

  test('online transition updates last online once and offline duration only after transition', () async {
    final clock = _MutableClock(start);
    final gateway = _FakeGateway(_sample());
    final store = _MemoryStore();
    final collector = _collector(_sample(), gateway: gateway, store: store, now: clock.call);

    final online = await collector.refresh();
    expect(online.status.value, NetworkOnlineStatus.online);
    expect(online.lastOnlineAt, start);
    clock.value = start.add(const Duration(minutes: 2));
    final repeatedOnline = await collector.refresh();
    expect(repeatedOnline.lastOnlineAt, start);

    gateway.current = _sample(type: 'none', status: 'offline', internet: 'unavailable');
    final offline = await collector.refresh();
    expect(offline.lastOnlineAt, start);
    expect(offline.offlineStartedAt, clock.value);
    expect(offline.offlineDuration.availability, CapabilityAvailability.available);
    expect(offline.offlineDuration.value, isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(store.lastOnlineAt, start);
  });

  test('first offline reading and post restart duration remain unknown', () async {
    final gateway = _FakeGateway(
      _sample(type: 'none', status: 'offline', internet: 'unavailable'),
    );
    final collector = _collector(
      _sample(type: 'none', status: 'offline', internet: 'unavailable'),
      gateway: gateway,
      now: () => start,
    );
    final initial = await collector.refresh();
    expect(initial.status.value, NetworkOnlineStatus.offline);
    expect(initial.offlineStartedAt, isNull);
    expect(initial.offlineDuration.availability, CapabilityAvailability.unknown);

    gateway.current = _sample();
    await collector.refresh();
    gateway.current = _sample(type: 'none', status: 'offline', internet: 'unavailable');
    await collector.refresh();
    await collector.stop();
    final restarted = await collector.refresh();
    expect(restarted.offlineStartedAt, isNull);
    expect(restarted.offlineDuration.availability, CapabilityAvailability.unknown);
  });

  test('offline to online clears the offline session and updates last online', () async {
    final gateway = _FakeGateway(_sample());
    final clock = _MutableClock(start);
    final collector = _collector(_sample(), gateway: gateway, now: clock.call);
    await collector.refresh();
    gateway.current = _sample(type: 'none', status: 'offline', internet: 'unavailable');
    final offline = await collector.refresh();
    expect(offline.offlineStartedAt, clock.value);

    clock.value = start.add(const Duration(minutes: 7));
    gateway.current = _sample();
    final online = await collector.refresh();
    expect(online.status.value, NetworkOnlineStatus.online);
    expect(online.lastOnlineAt, clock.value);
    expect(online.offlineStartedAt, isNull);
    expect(online.offlineDuration.availability, CapabilityAvailability.unavailable);
  });

  test('iOS usable path is online while Internet reachability remains unknown', () async {
    final collector = _collector(
      _sample(internet: 'unknown'),
      platform: 'ios',
      now: () => start,
    );
    final state = await collector.refresh();
    expect(state.status.value, NetworkOnlineStatus.online);
    expect(state.internet.value, InternetReachability.unknown);
    expect(state.internet.availability, CapabilityAvailability.unknown);
  });

  test('stored last online survives restart but offline duration does not', () async {
    final store = _MemoryStore()..lastOnlineAt = start;
    final collector = _collector(
      _sample(type: 'none', status: 'offline', internet: 'unavailable'),
      store: store,
      now: () => start.add(const Duration(hours: 2)),
    );
    final state = await collector.refresh();
    expect(state.lastOnlineAt, start);
    expect(state.offlineDuration.availability, CapabilityAvailability.unknown);
  });

  test('network state round-trips and can be included in a snapshot', () async {
    final state = await _collector(_sample(), now: () => start).refresh();
    final restored = NetworkState.fromJson(state.toJson());
    expect(restored.status.value, NetworkOnlineStatus.online);
    final snapshot = DeviceStateSnapshot(
      deviceId: 'device',
      collectedAt: start,
      capabilities: const {},
      network: state,
    );
    expect(
      DeviceStateSnapshot.fromJson(snapshot.toJson()).network?.connectivity.value,
      ConnectivityType.wifi,
    );
  });

  test('stale observation is distinguishable from current status', () async {
    final state = await _collector(_sample(), now: () => start).refresh();
    expect(state.freshnessAt(start), DataFreshness.fresh);
    expect(state.freshnessAt(start.add(const Duration(minutes: 16))), DataFreshness.stale);
  });

  test('network collection errors do not invalidate local battery data', () async {
    final battery = BatteryChargingCollector(
      gateway: _FakeBatteryGateway(const BatteryPlatformSample(
        percentage: 64,
        chargingState: 'discharging',
        chargingSource: 'unknown',
        chargingSourceSupported: true,
      )),
      now: () => start,
    );
    final network = _collector(
      _sample(),
      gateway: _FakeGateway(_sample())..readError = StateError('network'),
      now: () => start,
    );
    final provider = PlatformDeviceStateProvider(
      deviceId: () async => 'device',
      userId: () => 'user',
      adapter: _EmptyAdapter(),
      clock: () => start,
      logger: const NoopAppLogger(),
      batteryCollector: battery,
      networkCollector: network,
    );
    final snapshot = await provider.getCurrentState();
    expect(snapshot.battery?.percentage.value, 64);
    expect(snapshot.network?.status.availability, CapabilityAvailability.error);
  });

  test('network information contains no interface names or addresses', () async {
    final state = await _collector(_sample(), now: () => start).refresh();
    final json = state.toJson().toString();
    expect(json, isNot(contains('SSID')));
    expect(json, isNot(contains('192.168')));
  });
}

NetworkPlatformSample _sample({
  String type = 'wifi',
  String internet = 'available',
  String status = 'online',
}) => NetworkPlatformSample(
  connectivityType: type,
  internetReachability: internet,
  onlineStatus: status,
);

NetworkStateCollector _collector(
  NetworkPlatformSample sample, {
  NetworkPlatformGateway? gateway,
  NetworkObservationStore? store,
  DateTime Function()? now,
  String platform = 'android',
}) => NetworkStateCollector(
  gateway: gateway ?? _FakeGateway(sample, platform: platform),
  now: now ?? DateTime.now,
  store: store ?? _MemoryStore(),
);

class _FakeGateway implements NetworkPlatformGateway {
  _FakeGateway(this.current, {this.platform = 'android'});
  Object? current;
  Object? readError;
  final String platform;
  final _events = StreamController<Object?>.broadcast();

  @override
  String get platformName => platform;
  @override
  Future<Object?> readCurrent() async {
    if (readError != null) throw readError!;
    return current;
  }
  @override
  Stream<Object?> watchChanges() => _events.stream;
  void emit(Object? value) {
    current = value;
    _events.add(value);
  }
}

class _MemoryStore implements NetworkObservationStore {
  DateTime? lastOnlineAt;
  @override
  Future<DateTime?> readLastOnlineAt() async => lastOnlineAt;
  @override
  Future<void> writeLastOnlineAt(DateTime value) async {
    lastOnlineAt = value;
  }
}

class _MutableClock {
  _MutableClock(this.value);
  DateTime value;
  DateTime call() => value;
}

class _FakeBatteryGateway implements BatteryPlatformGateway {
  _FakeBatteryGateway(this.current);
  final Object? current;
  @override
  String get platformName => 'android';
  @override
  Future<Object?> readCurrent() async => current;
  @override
  Stream<Object?> watchChanges() => const Stream.empty();
}

class _EmptyAdapter implements PlatformDeviceStateAdapter {
  @override
  String get platformName => DevicePlatform.android.name;
  @override
  DeviceCapabilityStatus capabilityStatus(DeviceMetric capability) =>
      const DeviceCapabilityStatus(CapabilitySupport.unsupported);
  @override
  Future<StateObservation<Object?>> collect(DeviceMetric capability) async =>
      const StateObservation<Object?>(availability: CapabilityAvailability.unsupported);
}
