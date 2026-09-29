import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/logging/app_logger.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/domain/models/device_availability_evidence.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/services/activity_observation_store.dart';
import 'package:kam/features/device_state/domain/services/activity_state_collector.dart';
import 'package:kam/features/device_state/domain/services/device_availability_deriver.dart';
import 'package:kam/features/device_state/domain/sources/activity_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/platform_device_state_adapter.dart';

void main() {
  final start = DateTime.utc(2026, 9, 27, 12);
  const deriver = DeviceAvailabilityDeriver();

  StateObservation<int> observed(DateTime at, {int value = 42}) =>
      StateObservation<int>(
        availability: CapabilityAvailability.available,
        value: value,
        observedAt: at,
        updatedAt: at,
        source: 'test',
      );

  group('evidence-based derivation', () {
    test('fresh observations mean available', () {
      final evidence = deriver.derive(
        observations: [observed(start)],
        now: start.add(const Duration(minutes: 2)),
      );
      expect(evidence.availability, CapabilityAvailability.available);
      expect(evidence.lastConfirmedAvailableAt, start);
      expect(evidence.observedAt, start.add(const Duration(minutes: 2)));
      expect(evidence.source, 'local_observations');
    });

    test('old evidence becomes stale while keeping the confirmation time', () {
      final now = start.add(const Duration(hours: 3));
      final evidence = deriver.derive(observations: [observed(start)], now: now);
      expect(evidence.availability, CapabilityAvailability.stale);
      expect(evidence.lastConfirmedAvailableAt, start);
      expect(evidence.freshnessAt(now), DataFreshness.stale);
    });

    test('stale is distinguishable from unknown', () {
      final stale = deriver.derive(observations: [observed(start)], now: start);
      final unknown = deriver.derive(
        observations: const [],
        now: start,
      );
      expect(stale.availability, CapabilityAvailability.available);
      expect(stale.lastConfirmedAvailableAt, isNotNull);
      expect(unknown.availability, CapabilityAvailability.unknown);
      expect(unknown.lastConfirmedAvailableAt, isNull);
      expect(unknown.freshnessAt(start), DataFreshness.unknown);
    });

    test('all-unsupported observations stay unsupported', () {
      final evidence = deriver.derive(
        observations: const [
          StateObservation<Object?>(
            availability: CapabilityAvailability.unsupported,
          ),
          StateObservation<Object?>(
            availability: CapabilityAvailability.unsupported,
          ),
        ],
        now: start,
      );
      expect(evidence.availability, CapabilityAvailability.unsupported);
      expect(evidence.lastConfirmedAvailableAt, isNull);
    });

    test('mixed unsupported and unknown is unknown, never unsupported', () {
      final evidence = deriver.derive(
        observations: const [
          StateObservation<Object?>(
            availability: CapabilityAvailability.unsupported,
          ),
          StateObservation<Object?>(availability: CapabilityAvailability.unknown),
        ],
        now: start,
      );
      expect(evidence.availability, CapabilityAvailability.unknown);
    });

    test('permission denial is reported before other structural reasons', () {
      final evidence = deriver.derive(
        observations: const [
          StateObservation<Object?>(
            availability: CapabilityAvailability.unsupported,
          ),
          StateObservation<Object?>(
            availability: CapabilityAvailability.error,
            error: 'boom',
          ),
          StateObservation<Object?>(
            availability: CapabilityAvailability.permissionDenied,
          ),
        ],
        now: start,
      );
      expect(evidence.availability, CapabilityAvailability.permissionDenied);
    });

    test('errors carry a diagnostic instead of claiming unavailability', () {
      final evidence = deriver.derive(
        observations: const [
          StateObservation<Object?>(
            availability: CapabilityAvailability.error,
            error: 'Screen read failed (StateError).',
          ),
          StateObservation<Object?>(
            availability: CapabilityAvailability.unsupported,
          ),
        ],
        now: start,
      );
      expect(evidence.availability, CapabilityAvailability.error);
      expect(evidence.error, 'Screen read failed (StateError).');
    });

    test('unavailable is used when nothing failed but nothing is present', () {
      final evidence = deriver.derive(
        observations: const [
          StateObservation<Object?>(availability: CapabilityAvailability.unavailable),
        ],
        now: start,
      );
      expect(evidence.availability, CapabilityAvailability.unavailable);
    });
  });

  group('activity evidence', () {
    test('a recent observed activity signal alone confirms availability', () {
      final evidence = deriver.derive(
        observations: const [],
        lastObservedActivityAt: start,
        now: start.add(const Duration(minutes: 5)),
      );
      expect(evidence.availability, CapabilityAvailability.available);
      expect(evidence.lastConfirmedAvailableAt, start);
    });

    test('an old restored timestamp is stale history, not current availability', () {
      final evidence = deriver.derive(
        observations: const [],
        lastObservedActivityAt: start,
        now: start.add(const Duration(days: 1)),
      );
      expect(evidence.availability, CapabilityAvailability.stale);
      expect(evidence.lastConfirmedAvailableAt, start);
    });

    test('future evidence from clock skew is treated as fresh, not rejected', () {
      final evidence = deriver.derive(
        observations: const [],
        lastObservedActivityAt: start.add(const Duration(minutes: 1)),
        now: start,
      );
      expect(evidence.availability, CapabilityAvailability.available);
    });

    test('missing evidence never implies a power state', () {
      final evidence = deriver.derive(observations: const [], now: start);
      // The model has no "phone off" value at all; nothing observed means
      // unknown, which is the only honest answer.
      expect(evidence.availability, CapabilityAvailability.unknown);
      expect(
        CapabilityAvailability.values.map((value) => value.name),
        isNot(contains('phonePoweredOff')),
      );
    });
  });

  group('serialization', () {
    test('evidence round-trips availability, timestamps and error detail', () {
      const evidence = DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.error,
        lastConfirmedAvailableAt: null,
        observedAt: null,
        source: 'local_observations',
        error: 'boom',
      );
      final restored = DeviceAvailabilityEvidence.fromJson(evidence.toJson());
      expect(restored.availability, CapabilityAvailability.error);
      expect(restored.lastConfirmedAvailableAt, isNull);
      expect(restored.observedAt, isNull);
      expect(restored.source, 'local_observations');
      expect(restored.error, 'boom');

      final dated = DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.stale,
        lastConfirmedAvailableAt: start,
        observedAt: start.add(const Duration(hours: 2)),
        source: 'local_observations',
      );
      final restoredDated = DeviceAvailabilityEvidence.fromJson(dated.toJson());
      expect(restoredDated.availability, CapabilityAvailability.stale);
      expect(restoredDated.lastConfirmedAvailableAt, start);
      expect(restoredDated.observedAt, start.add(const Duration(hours: 2)));
    });

    test('freshness follows the confirmation time, not the assessment time', () {
      final evidence = DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.stale,
        lastConfirmedAvailableAt: start,
        observedAt: start.add(const Duration(days: 5)),
      );
      expect(evidence.freshnessAt(start), DataFreshness.fresh);
      expect(
        evidence.freshnessAt(start.add(const Duration(minutes: 16))),
        DataFreshness.stale,
      );
      expect(
        DeviceAvailabilityEvidence.unknown().freshnessAt(start),
        DataFreshness.unknown,
      );
    });
  });

  group('provider integration', () {
    test('snapshots carry derived availability', () async {
      final provider = PlatformDeviceStateProvider(
        deviceId: () async => 'device',
        userId: () => 'user',
        adapter: _AllSupportedAdapter(start),
        clock: () => start,
        logger: const NoopAppLogger(),
      );
      final snapshot = await provider.getCurrentState();
      expect(snapshot.availability, isNotNull);
      expect(snapshot.availability!.availability, CapabilityAvailability.available);
      expect(snapshot.availability!.lastConfirmedAvailableAt, start);
    });

    test('a provider with no observation source reports unsupported, not available', () async {
      final provider = PlatformDeviceStateProvider(
        deviceId: () async => 'device',
        userId: () => 'user',
        adapter: _EmptyAdapter(),
        clock: () => start,
        logger: const NoopAppLogger(),
      );
      final snapshot = await provider.getCurrentState();
      expect(snapshot.availability!.availability, CapabilityAvailability.unsupported);
      expect(snapshot.availability!.lastConfirmedAvailableAt, isNull);
    });

    test('restart: restored history older than the window is stale, never current', () async {
      final activity = ActivityStateCollector(
        gateway: _FakeGateway(),
        store: _MemoryStore()..lastObserved = start,
        now: () => start.add(const Duration(hours: 2)),
      );
      final provider = PlatformDeviceStateProvider(
        deviceId: () async => 'device',
        userId: () => 'user',
        adapter: _EmptyAdapter(),
        clock: () => start.add(const Duration(hours: 2)),
        logger: const NoopAppLogger(),
        activityCollector: activity,
      );
      final snapshot = await provider.getCurrentState();
      expect(snapshot.activity!.lastObservedActivityAt, start);
      expect(snapshot.availability!.availability, CapabilityAvailability.stale);
      expect(snapshot.availability!.lastConfirmedAvailableAt, start);
    });

    test('restart: recent restored history still counts as evidence', () async {
      final activity = ActivityStateCollector(
        gateway: _FakeGateway(),
        store: _MemoryStore()..lastObserved = start,
        now: () => start.add(const Duration(minutes: 5)),
      );
      final provider = PlatformDeviceStateProvider(
        deviceId: () async => 'device',
        userId: () => 'user',
        adapter: _EmptyAdapter(),
        clock: () => start.add(const Duration(minutes: 5)),
        logger: const NoopAppLogger(),
        activityCollector: activity,
      );
      final snapshot = await provider.getCurrentState();
      expect(snapshot.availability!.availability, CapabilityAvailability.available);
      expect(snapshot.availability!.lastConfirmedAvailableAt, start);
    });
  });
}

class _FakeGateway implements ActivityPlatformGateway {
  @override
  String get platformName => 'nonAndroid';

  @override
  Future<Object?> readCurrent() async => const ActivityPlatformSample(
    screenStateSupported: false,
  );

  @override
  Stream<Object?> watchChanges() => const Stream.empty();
}

class _MemoryStore implements ActivityObservationStore {
  DateTime? lastObserved;

  @override
  Future<DateTime?> readLastObservedActivityAt() async => lastObserved;

  @override
  Future<void> writeLastObservedActivityAt(DateTime value) async {
    lastObserved = value;
  }
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

class _AllSupportedAdapter implements PlatformDeviceStateAdapter {
  _AllSupportedAdapter(this.observedAt);
  final DateTime observedAt;

  @override
  String get platformName => DevicePlatform.android.name;

  @override
  DeviceCapabilityStatus capabilityStatus(DeviceMetric capability) =>
      const DeviceCapabilityStatus(CapabilitySupport.supported);

  @override
  Future<StateObservation<Object?>> collect(DeviceMetric capability) async =>
      StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: capability.name,
        observedAt: observedAt,
        updatedAt: observedAt,
        source: 'test_adapter',
      );
}
