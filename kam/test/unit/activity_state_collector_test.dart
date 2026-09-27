import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/logging/app_logger.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/domain/models/activity_state.dart';
import 'package:kam/features/device_state/domain/models/device_availability_evidence.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/services/activity_observation_store.dart';
import 'package:kam/features/device_state/domain/services/activity_state_collector.dart';
import 'package:kam/features/device_state/domain/services/battery_charging_collector.dart';
import 'package:kam/features/device_state/domain/sources/activity_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/battery_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/platform_device_state_adapter.dart';

void main() {
  final start = DateTime.utc(2026, 9, 27, 12);

  group('screen state', () {
    for (final value in ['on', 'off']) {
      test('normalizes screen state $value', () async {
        final collector = _collector(_sample(screen: value), now: () => start);
        final state = await collector.refresh();
        expect(
          state.screenState.value,
          value == 'on' ? DeviceScreenState.on : DeviceScreenState.off,
        );
        expect(state.screenState.availability, CapabilityAvailability.available);
        expect(state.screenState.observedAt, start);
        expect(state.freshnessAt(start), DataFreshness.fresh);
      });
    }

    test('platform-reported unknown stays unknown, never on or off', () async {
      final state = await _collector(
        _sample(screen: 'unknown'),
        now: () => start,
      ).refresh();
      expect(state.screenState.availability, CapabilityAvailability.unknown);
      expect(state.screenState.value, DeviceScreenState.unknown);
    });

    test('missing screen value is unavailable and malformed value is error', () async {
      final missing = await _collector(
        ActivityPlatformSample(screenStateSupported: true),
        now: () => start,
      ).refresh();
      expect(missing.screenState.availability, CapabilityAvailability.unavailable);

      final malformed = await _collector(
        _sample(screen: 'banana'),
        now: () => start,
      ).refresh();
      expect(malformed.screenState.availability, CapabilityAvailability.error);
      expect(malformed.screenState.error, isNotNull);
    });

    test('iOS style platform reports screen state as unsupported', () async {
      final collector = _collector(_sample(), platform: 'ios', now: () => start);
      final state = await collector.refresh();
      expect(state.screenState.availability, CapabilityAvailability.unsupported);
      expect(state.screenState.value, isNull);
      expect(
        collector.capabilityStatus[DeviceMetric.screenState]?.support,
        CapabilitySupport.unsupported,
      );
      expect(
        collector.capabilityStatus[DeviceMetric.appLifecycle]?.support,
        CapabilitySupport.supported,
      );
    });

    test('sample without support flag is unsupported', () async {
      final state = await _collector(
        const ActivityPlatformSample(screenStateSupported: false),
        now: () => start,
      ).refresh();
      expect(state.screenState.availability, CapabilityAvailability.unsupported);
    });

    test('stale screen observations are distinguishable from current ones', () async {
      final state = await _collector(_sample(), now: () => start).refresh();
      expect(state.freshnessAt(start), DataFreshness.fresh);
      expect(
        state.freshnessAt(start.add(const Duration(minutes: 16))),
        DataFreshness.stale,
      );
    });
  });

  group('lastObservedActivityAt', () {
    test('reading the screen never fabricates an activity timestamp', () async {
      final collector = _collector(_sample(screen: 'on'), now: () => start);
      await collector.refresh();
      expect(collector.lastObservedActivityAt, isNull);
      await collector.refresh();
      expect(collector.lastObservedActivityAt, isNull);
    });

    test('an observed screen transition updates the timestamp once', () async {
      final clock = _MutableClock(start);
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final collector = _collector(_sample(screen: 'off'), gateway: gateway, now: clock.call);
      await collector.start();
      expect(collector.lastObservedActivityAt, isNull);

      clock.value = start.add(const Duration(minutes: 3));
      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);
      expect(collector.lastObservedActivityAt, clock.value);

      // Repeated unchanged readings must not restamp it.
      clock.value = start.add(const Duration(minutes: 5));
      await collector.refresh();
      expect(collector.lastObservedActivityAt, start.add(const Duration(minutes: 3)));
      await collector.stop();
    });

    test('application start does not create a timestamp; observed lifecycle transitions do', () async {
      final clock = _MutableClock(start);
      final collector = _collector(_sample(), now: clock.call);
      // First report only establishes the phase (app starting is not an
      // observed activity event).
      collector.reportAppLifecycle(AppLifecyclePhase.foreground);
      expect(collector.lastObservedActivityAt, isNull);

      clock.value = start.add(const Duration(minutes: 10));
      collector.reportAppLifecycle(AppLifecyclePhase.background);
      expect(collector.lastObservedActivityAt, clock.value);

      // A repeated identical report is not a transition.
      clock.value = start.add(const Duration(minutes: 11));
      collector.reportAppLifecycle(AppLifecyclePhase.background);
      expect(collector.lastObservedActivityAt, start.add(const Duration(minutes: 10)));
    });
  });

  group('app lifecycle stays separate from screen state', () {
    test('background lifecycle never rewrites the screen observation', () async {
      final collector = _collector(_sample(screen: 'on'), now: () => start);
      collector.reportAppLifecycle(AppLifecyclePhase.foreground);
      final state = await collector.refresh();
      expect(state.screenState.value, DeviceScreenState.on);
      expect(state.appLifecycle.value, AppLifecyclePhase.foreground);

      collector.reportAppLifecycle(AppLifecyclePhase.background);
      final after = collector.current;
      // Scenario C: app background does not become screen off or activity none
      // while the observed screen signal is still ON.
      expect(after.screenState.value, DeviceScreenState.on);
      expect(after.appLifecycle.value, AppLifecyclePhase.background);
      expect(after.activityStatus.value, ActivityStatus.activityDetected);
    });

    test('every lifecycle phase is representable and serialized by name', () async {
      final phases = [
        AppLifecyclePhase.foreground,
        AppLifecyclePhase.background,
        AppLifecyclePhase.inactive,
        AppLifecyclePhase.hidden,
        AppLifecyclePhase.detached,
      ];
      for (final phase in phases) {
        final collector = _collector(_sample(), now: () => start);
        collector.reportAppLifecycle(phase);
        expect(collector.current.appLifecycle.value, phase);
        expect(collector.current.appLifecycle.availability, CapabilityAvailability.available);
        final restored = ActivityState.fromJson(collector.current.toJson());
        expect(restored.appLifecycle.value, phase);
      }
    });

    test('status derives from app lifecycle when screen is unsupported', () async {
      final collector = _collector(_sample(), platform: 'ios', now: () => start);
      final initial = await collector.refresh();
      expect(initial.activityStatus.value, ActivityStatus.unknown);

      collector.reportAppLifecycle(AppLifecyclePhase.foreground);
      expect(collector.current.activityStatus.value, ActivityStatus.activityDetected);
      expect(collector.current.screenState.availability, CapabilityAvailability.unsupported);

      collector.reportAppLifecycle(AppLifecyclePhase.background);
      expect(
        collector.current.activityStatus.value,
        ActivityStatus.noActivityObserved,
      );
      // The first lifecycle report was the app starting, so no activity
      // timestamp exists yet; the observed transition does create one.
      expect(collector.lastObservedActivityAt, start);
    });

    test('no signals available means unknown activity, never noActivityObserved', () async {
      final state = await _collector(
        ActivityPlatformSample(screenStateSupported: true),
        now: () => start,
      ).refresh();
      expect(state.activityStatus.availability, CapabilityAvailability.unknown);
      expect(state.activityStatus.value, ActivityStatus.unknown);
    });
  });

  group('activity duration', () {
    test('first detection without an observed transition has unknown duration', () async {
      final collector = _collector(_sample(screen: 'on'), now: () => start);
      final state = await collector.refresh();
      expect(state.activityStatus.value, ActivityStatus.activityDetected);
      expect(state.activityStartedAt, isNull);
      expect(state.activityDuration.availability, CapabilityAvailability.unknown);
    });

    test('an observed off-to-on transition starts a session', () async {
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final collector = _collector(_sample(screen: 'off'), gateway: gateway, now: () => start);
      await collector.start();
      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);

      final state = collector.current;
      expect(state.activityStartedAt, start);
      expect(state.activityDuration.availability, CapabilityAvailability.available);
      expect(state.activityDuration.value, isNotNull);

      gateway.emit(_sample(screen: 'off'));
      await Future<void>.delayed(Duration.zero);
      expect(collector.current.activityStartedAt, isNull);
      expect(
        collector.current.activityDuration.availability,
        CapabilityAvailability.unavailable,
      );
      await collector.stop();
    });

    test('monitoring gaps invalidate the session without erasing history', () async {
      final clock = _MutableClock(start);
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final collector = _collector(_sample(screen: 'off'), gateway: gateway, now: clock.call);
      await collector.start();
      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);
      expect(collector.current.activityStartedAt, start);

      await collector.stop();
      clock.value = start.add(const Duration(minutes: 8));
      final resumed = await collector.refresh();
      // Transitions may have been missed during the gap: no session start may
      // be re-anchored, but the historical timestamp survives.
      expect(resumed.activityStartedAt, isNull);
      expect(resumed.activityDuration.availability, CapabilityAvailability.unknown);
      expect(resumed.lastObservedActivityAt, start);
    });

    test('elapsed duration uses a monotonic clock across wall-clock jumps', () async {
      final clock = _MutableClock(start);
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final collector = _collector(_sample(screen: 'off'), gateway: gateway, now: clock.call);
      await collector.start();
      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);

      clock.value = start.add(const Duration(hours: 3));
      final state = await collector.refresh();
      expect(state.activityDuration.availability, CapabilityAvailability.available);
      expect(state.activityDuration.value! < const Duration(hours: 3), isTrue);
      await collector.stop();
    });
  });

  group('restart and persistence', () {
    test('a restored timestamp keeps its historical time after restart', () async {
      final store = _MemoryStore()..lastObserved = start;
      final later = start.add(const Duration(hours: 20));
      final collector = _collector(_sample(screen: 'on'), store: store, now: () => later);
      final state = await collector.refresh();
      expect(state.lastObservedActivityAt, start);
      expect(store.writes, 0, reason: 'restore must not rewrite history');
    });

    test('a future stored timestamp is ignored', () async {
      final store = _MemoryStore()..lastObserved = start.add(const Duration(days: 1));
      final collector = _collector(_sample(), store: store, now: () => start);
      await collector.refresh();
      expect(collector.lastObservedActivityAt, isNull);
    });

    test('storage failure degrades to no history instead of crashing', () async {
      final collector = _collector(
        _sample(),
        store: _ThrowingStore(),
        now: () => start,
      );
      final state = await collector.refresh();
      expect(state.lastObservedActivityAt, isNull);
      // A later observed transition still works; only persistence is lost.
      collector.reportAppLifecycle(AppLifecyclePhase.foreground);
      collector.reportAppLifecycle(AppLifecyclePhase.background);
      expect(collector.lastObservedActivityAt, start);
    });

    test('observed transitions are persisted exactly once per change', () async {
      final store = _MemoryStore();
      final clock = _MutableClock(start);
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final collector = _collector(
        _sample(screen: 'off'),
        gateway: gateway,
        store: store,
        now: clock.call,
      );
      await collector.start();
      expect(store.writes, 0);
      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1);
      expect(store.lastObserved, start);
      await collector.stop();
    });
  });

  group('error isolation', () {
    test('a failed screen read is an error observation, not an exception', () async {
      final gateway = _FakeGateway(_sample())..readError = StateError('test');
      final collector = _collector(_sample(), gateway: gateway, now: () => start);
      final state = await collector.refresh();
      expect(state.screenState.availability, CapabilityAvailability.error);
      expect(state.screenState.error, isNotNull);
      expect(state.screenState.observedAt, start);
    });

    test('activity failure does not break battery collection', () async {
      final battery = BatteryChargingCollector(
        gateway: _FakeBatteryGateway(
          const BatteryPlatformSample(
            percentage: 64,
            chargingState: 'discharging',
            chargingSource: 'unknown',
            chargingSourceSupported: true,
          ),
        ),
        now: () => start,
      );
      final activity = _collector(
        _sample(),
        gateway: _FakeGateway(_sample())..readError = StateError('screen'),
        now: () => start,
      );
      final provider = PlatformDeviceStateProvider(
        deviceId: () async => 'device',
        userId: () => 'user',
        adapter: _EmptyAdapter(),
        clock: () => start,
        logger: const NoopAppLogger(),
        batteryCollector: battery,
        activityCollector: activity,
      );

      final snapshot = await provider.getCurrentState();
      expect(snapshot.battery?.percentage.value, 64);
      expect(snapshot.activity?.screenState.availability, CapabilityAvailability.error);
      expect(snapshot.availability, isNotNull);
      // Battery evidence still proves availability despite the screen error.
      expect(snapshot.availability!.availability, CapabilityAvailability.available);
    });
  });

  group('event monitoring', () {
    test('starts once, emits native transitions, and cancels cleanly', () async {
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final collector = _collector(_sample(screen: 'off'), gateway: gateway, now: () => start);
      await collector.start();
      await collector.start();
      expect(collector.isStarted, isTrue);
      expect(gateway._events.hasListener, isTrue);

      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);
      expect(collector.current.screenState.value, DeviceScreenState.on);
      expect(collector.lastObservedActivityAt, start);

      await collector.stop();
      expect(collector.isStarted, isFalse);
      expect(gateway._events.hasListener, isFalse);
    });

    test('watch stream yields the current state and stops on cancel', () async {
      final gateway = _FakeGateway(_sample(screen: 'on'));
      final collector = _collector(_sample(screen: 'on'), gateway: gateway, now: () => start);
      final states = <ActivityState>[];
      final subscription = collector.watchActivityState().listen(states.add);
      await Future<void>.delayed(Duration.zero);
      expect(states, isNotEmpty);
      expect(states.first.screenState.value, DeviceScreenState.on);
      await subscription.cancel();
      expect(collector.isStarted, isFalse);
    });

    test('unsupported platforms publish unsupported without touching channels', () async {
      final gateway = _FakeGateway(_sample(), platformName: 'unknown');
      final collector = _collector(_sample(), gateway: gateway, now: () => start);
      final state = await collector.refresh();
      expect(state.screenState.availability, CapabilityAvailability.unsupported);
      expect(gateway.reads, 0);
    });
  });

  group('serialization', () {
    test('a full activity state round-trips every field', () async {
      final clock = _MutableClock(start);
      final gateway = _FakeGateway(_sample(screen: 'off'));
      final store = _MemoryStore();
      final collector = _collector(
        _sample(screen: 'off'),
        gateway: gateway,
        store: store,
        now: clock.call,
      );
      await collector.start();
      clock.value = start.add(const Duration(minutes: 2));
      gateway.emit(_sample(screen: 'on'));
      await Future<void>.delayed(Duration.zero);
      collector.reportAppLifecycle(AppLifecyclePhase.foreground);

      final state = collector.current;
      final restored = ActivityState.fromJson(state.toJson());
      expect(restored.screenState.value, DeviceScreenState.on);
      expect(restored.screenState.source, 'android');
      expect(restored.activityStatus.value, ActivityStatus.activityDetected);
      expect(restored.appLifecycle.value, AppLifecyclePhase.foreground);
      expect(restored.appLifecycle.source, 'app_lifecycle');
      expect(restored.lastObservedActivityAt, start.add(const Duration(minutes: 2)));
      expect(restored.activityStartedAt, start.add(const Duration(minutes: 2)));
      expect(restored.activityDuration.availability, CapabilityAvailability.available);
      // The serialized unit is whole milliseconds, so a sub-millisecond
      // reading truncates; it must never round-trip upward.
      expect(restored.activityDuration.value! <= state.activityDuration.value!, isTrue);
      expect(restored.activityDuration.value! >= Duration.zero, isTrue);
      await collector.stop();
    });

    test('activity and availability survive a snapshot round-trip', () async {
      final state = await _collector(_sample(screen: 'on'), now: () => start).refresh();
      final evidence = DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.available,
        lastConfirmedAvailableAt: start,
        observedAt: start,
        source: 'local_observations',
      );
      final snapshot = DeviceStateSnapshot(
        deviceId: 'device',
        userId: 'owner',
        collectedAt: start,
        capabilities: const {},
        activity: state,
        availability: evidence,
      );
      final restored = DeviceStateSnapshot.fromJson(snapshot.toJson());
      expect(restored.activity?.screenState.value, DeviceScreenState.on);
      expect(restored.activity?.screenState.observedAt, start);
      expect(restored.availability?.availability, CapabilityAvailability.available);
      expect(restored.availability?.lastConfirmedAvailableAt, start);
    });

    test('unsupported screen state round-trips without inventing a value', () async {
      final state = await _collector(_sample(), platform: 'ios', now: () => start).refresh();
      final restored = ActivityState.fromJson(state.toJson());
      expect(restored.screenState.availability, CapabilityAvailability.unsupported);
      expect(restored.screenState.value, isNull);
      expect(restored.screenState.observedAt, isNull);
    });
  });
}

ActivityPlatformSample _sample({String? screen = 'on'}) =>
    ActivityPlatformSample(screenStateSupported: true, screenState: screen);

ActivityStateCollector _collector(
  ActivityPlatformSample sample, {
  ActivityPlatformGateway? gateway,
  ActivityObservationStore? store,
  DateTime Function()? now,
  String platform = 'android',
}) => ActivityStateCollector(
  gateway: gateway ?? _FakeGateway(sample, platformName: platform),
  now: now ?? DateTime.now,
  store: store ?? _MemoryStore(),
);

class _FakeGateway implements ActivityPlatformGateway {
  _FakeGateway(this.current, {this.platformName = 'android'});
  Object? current;
  Object? readError;
  int reads = 0;
  @override
  final String platformName;
  final _events = StreamController<Object?>.broadcast();

  @override
  Future<Object?> readCurrent() async {
    reads++;
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

class _MemoryStore implements ActivityObservationStore {
  DateTime? lastObserved;
  int writes = 0;

  @override
  Future<DateTime?> readLastObservedActivityAt() async => lastObserved;

  @override
  Future<void> writeLastObservedActivityAt(DateTime value) async {
    lastObserved = value;
    writes++;
  }
}

class _ThrowingStore implements ActivityObservationStore {
  @override
  Future<DateTime?> readLastObservedActivityAt() async =>
      throw StateError('storage unavailable');

  @override
  Future<void> writeLastObservedActivityAt(DateTime value) async =>
      throw StateError('storage unavailable');
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
