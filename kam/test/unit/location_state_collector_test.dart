import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/logging/app_logger.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/features/device_state/data/providers/platform_device_state_provider.dart';
import 'package:kam/features/device_state/domain/models/device_location_state.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/services/activity_observation_store.dart';
import 'package:kam/features/device_state/domain/services/activity_state_collector.dart';
import 'package:kam/features/device_state/domain/services/battery_charging_collector.dart';
import 'package:kam/features/device_state/domain/services/location_observation_store.dart';
import 'package:kam/features/device_state/domain/services/location_state_collector.dart';
import 'package:kam/features/device_state/domain/sources/activity_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/battery_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/location_platform_source.dart';
import 'package:kam/features/device_state/domain/sources/platform_device_state_adapter.dart';
import 'package:kam/features/location/domain/models/location_state.dart';

void main() {
  final start = DateTime.utc(2026, 9, 27, 12);

  group('permission states', () {
    test('not requested yet is permission denied with a precise reason', () async {
      final gateway = _FakeGateway(
        status: _status(permission: 'notDetermined'),
      );
      final collector = _collector(gateway: gateway, now: () => start);
      final state = await collector.refresh();

      expect(state.location.availability, CapabilityAvailability.permissionDenied);
      expect(state.location.permissionState, DevicePermissionState.notDetermined);
      expect(state.permission.value, DevicePermissionState.notDetermined);
      expect(gateway.fixReads, 0, reason: 'no fix may be requested without permission');
      expect(
        collector.capabilityStatus[DeviceMetric.location]?.support,
        CapabilitySupport.permissionRequired,
      );
    });

    test('denied stays distinguishable from not determined', () async {
      final collector = _collector(
        gateway: _FakeGateway(status: _status(permission: 'denied')),
        now: () => start,
      );
      final state = await collector.refresh();
      expect(state.location.availability, CapabilityAvailability.permissionDenied);
      expect(state.location.permissionState, DevicePermissionState.denied);
    });

    test('permanently denied never prompts again', () async {
      final gateway = _FakeGateway(
        status: _status(permission: 'permanentlyDenied'),
      );
      final collector = _collector(gateway: gateway, now: () => start);
      await collector.refresh();
      final state = await collector.requestPermission();

      expect(gateway.permissionRequests, 0);
      expect(state.location.permissionState, DevicePermissionState.permanentlyDenied);
      expect(state.location.availability, CapabilityAvailability.permissionDenied);
    });

    test('OS-restricted permission never prompts and is reported as restricted', () async {
      final gateway = _FakeGateway(status: _status(permission: 'restricted'));
      final collector = _collector(gateway: gateway, now: () => start);
      await collector.refresh();
      final state = await collector.requestPermission();

      expect(gateway.permissionRequests, 0);
      expect(state.permission.value, DevicePermissionState.restricted);
    });

    test('a granted permission yields a fix and a supported capability', () async {
      final gateway = _FakeGateway(
        status: _status(permission: 'granted', precise: true),
        fix: _fix(latitude: 31.9045, longitude: 35.2034, accuracy: 18),
      );
      final collector = _collector(gateway: gateway, now: () => start);
      final state = await collector.refresh();

      expect(state.location.availability, CapabilityAvailability.available);
      expect(state.location.value?.coordinate.latitude, 31.9045);
      expect(state.location.value?.accuracyMeters, 18);
      expect(state.location.observedAt, start);
      expect(state.permission.value, DevicePermissionState.granted);
      expect(
        collector.capabilityStatus[DeviceMetric.location]?.support,
        CapabilitySupport.supported,
      );
      expect(
        collector.capabilityStatus[DeviceMetric.preciseLocation]?.support,
        CapabilitySupport.supported,
      );
    });

    test('an explicit grant request reads a fix afterwards', () async {
      final gateway = _FakeGateway(status: _status(permission: 'notDetermined'));
      final collector = _collector(gateway: gateway, now: () => start);
      await collector.refresh();
      expect(gateway.fixReads, 0);

      gateway.status = _status(permission: 'granted');
      gateway.fix = _fix(latitude: 31.9, longitude: 35.2);
      final state = await collector.requestPermission();

      expect(gateway.permissionRequests, 1);
      expect(state.permission.value, DevicePermissionState.granted);
      expect(state.location.availability, CapabilityAvailability.available);
    });
  });

  group('location service state', () {
    test('service disabled is distinct from permission denied', () async {
      final gateway = _FakeGateway(
        status: _status(permission: 'granted', serviceEnabled: false),
      );
      final collector = _collector(gateway: gateway, now: () => start);
      final state = await collector.refresh();

      expect(state.location.availability, CapabilityAvailability.serviceDisabled);
      expect(state.serviceState, LocationServiceState.disabled);
      expect(state.location.permissionState, DevicePermissionState.granted);
      expect(gateway.fixReads, 0);
    });

    test('a successful status read reports the service as on', () async {
      final state = await _collector(
        gateway: _FakeGateway(
          status: _status(),
          fix: _fix(latitude: 31.9, longitude: 35.2),
        ),
        now: () => start,
      ).refresh();
      expect(state.serviceState, LocationServiceState.enabled);
      expect(state.location.availability, CapabilityAvailability.available);
    });

    test('a failed status read leaves the service state unknown, not off', () async {
      final gateway = _FakeGateway(status: _status())
        ..statusException = StateError('status');
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.serviceState, LocationServiceState.unknown);
      expect(state.location.availability, CapabilityAvailability.error);
    });

    test('unsupported platforms claim nothing and never call the gateway', () async {
      final gateway = _FakeGateway(status: _status(), platformName: 'unknown');
      final collector = _collector(gateway: gateway, now: () => start);
      final state = await collector.refresh();

      expect(state.location.availability, CapabilityAvailability.unsupported);
      expect(gateway.statusReads, 0);
      expect(gateway.fixReads, 0);
      expect(
        collector.capabilityStatus[DeviceMetric.location]?.support,
        CapabilitySupport.unsupported,
      );
      expect(
        collector.capabilityStatus[DeviceMetric.backgroundLocation]?.support,
        CapabilitySupport.unsupported,
      );
      expect(
        collector.capabilityStatus[DeviceMetric.homeLocation]?.support,
        CapabilitySupport.supported,
      );
    });
  });

  group('fix validation and accuracy', () {
    test('invalid coordinates are rejected rather than clamped', () async {
      final gateway = _FakeGateway(
        status: _status(),
        fix: _fix(latitude: 200, longitude: 35),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.error);
      expect(state.location.value, isNull);
      expect(state.location.error, contains('invalid coordinate'));
    });

    test('an incomplete fix is an error, never half a location', () async {
      final gateway = _FakeGateway(
        status: _status(),
        fix: const LocationFixSample(latitude: 31.9),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.error);
      expect(state.location.value, isNull);
    });

    test('an out-of-range accuracy is rejected', () async {
      final gateway = _FakeGateway(
        status: _status(),
        fix: _fix(latitude: 31.9, longitude: 35.2, accuracy: -5),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.error);
    });

    test('a timeout is reported as a temporary failure with a reason', () async {
      final gateway = _FakeGateway(
        status: _status(),
        fix: const LocationFixSample(error: 'timeout'),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.error);
      expect(state.location.error, contains('timed out'));
    });

    test('a disabled service reported by the provider is understood', () async {
      final gateway = _FakeGateway(
        status: _status(),
        fix: const LocationFixSample(error: 'disabled'),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.error);
      expect(state.location.error, contains('disabled'));
    });

    test('a platform exception becomes a normalized error', () async {
      final gateway = _FakeGateway(status: _status())..fixException = StateError('boom');
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.error);
      expect(state.location.error, contains('StateError'));
    });

    test('a status read failure never invents a location', () async {
      final gateway = _FakeGateway(status: _status())
        ..statusException = StateError('status');
      final collector = _collector(gateway: gateway, now: () => start);
      final state = await collector.refresh();
      expect(state.permission.availability, CapabilityAvailability.unknown);
      expect(state.location.availability, CapabilityAvailability.error);
      expect(state.location.value, isNull);
      expect(gateway.fixReads, 0);
    });

    test('missing accuracy stays missing and does not block the fix', () async {
      final gateway = _FakeGateway(
        status: _status(),
        fix: _fix(latitude: 31.9, longitude: 35.2, accuracy: null),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.availability, CapabilityAvailability.available);
      expect(state.location.value?.accuracyMeters, isNull);
    });

    test('reduced accuracy is carried through and never upgraded', () async {
      final gateway = _FakeGateway(
        status: _status(permission: 'granted', precise: false),
        fix: _fix(latitude: 31.9, longitude: 35.2, approximate: true, accuracy: 900),
      );
      final collector = _collector(gateway: gateway, now: () => start);
      final state = await collector.refresh();

      expect(state.location.value?.approximate, isTrue);
      expect(state.location.value?.accuracyMeters, 900);
      expect(
        collector.capabilityStatus[DeviceMetric.preciseLocation]?.support,
        CapabilitySupport.permissionRequired,
      );
      expect(
        collector.capabilityStatus[DeviceMetric.approximateLocation]?.support,
        CapabilitySupport.supported,
      );
    });

    test('the platform fix time is used, and a future clock is clamped to now', () async {
      final platformTime = start.subtract(const Duration(minutes: 4));
      final gateway = _FakeGateway(
        status: _status(),
        fix: _fix(
          latitude: 31.9,
          longitude: 35.2,
          observedAt: platformTime,
        ),
      );
      final state = await _collector(gateway: gateway, now: () => start).refresh();
      expect(state.location.observedAt, platformTime);

      final futureGateway = _FakeGateway(
        status: _status(),
        fix: _fix(
          latitude: 31.9,
          longitude: 35.2,
          observedAt: start.add(const Duration(hours: 1)),
        ),
      );
      final clamped = await _collector(gateway: futureGateway, now: () => start).refresh();
      expect(clamped.location.observedAt, start);
    });
  });

  group('last known location and restart', () {
    test('a live fix is persisted once', () async {
      final store = _MemoryStore();
      final gateway = _FakeGateway(
        status: _status(),
        fix: _fix(latitude: 31.9045, longitude: 35.2034, accuracy: 20),
      );
      final collector = _collector(gateway: gateway, store: store, now: () => start);
      await collector.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(store.writes, 1);
      expect(store.fix?.coordinate.latitude, 31.9045);
      expect(store.fix?.observedAt, start);
    });

    test('a restored fix keeps its original timestamp and is never re-stamped', () async {
      final storedTime = start.subtract(const Duration(minutes: 47));
      final store = _MemoryStore()
        ..fix = LocationFix(
          coordinate: const Coordinate(latitude: 31.9038, longitude: 35.2034),
          observedAt: storedTime,
          accuracyMeters: 32,
        );
      final gateway = _FakeGateway(status: _status(permission: 'denied'));
      final collector = _collector(gateway: gateway, store: store, now: () => start);
      final state = await collector.refresh();

      expect(state.lastKnownLocation.observedAt, storedTime);
      expect(state.lastKnownLocation.value?.observedAt, storedTime);
      expect(state.lastKnownLocation.value?.accuracyMeters, 32);
      expect(store.writes, 0, reason: 'reading history must not rewrite it');
      // The permission blocks a current fix; the history stays historical.
      expect(state.location.availability, CapabilityAvailability.permissionDenied);
      expect(state.freshnessAt(start), DataFreshness.stale);
    });

    test('an old fix is stale and never presented as current', () async {
      final store = _MemoryStore()
        ..fix = LocationFix(
          coordinate: const Coordinate(latitude: 31.9, longitude: 35.2),
          observedAt: start.subtract(const Duration(hours: 4)),
          accuracyMeters: 30,
        );
      // Permission is fine but the provider has no fresh fix: the retained
      // history must be labelled stale rather than current.
      final state = await _collector(
        gateway: _FakeGateway(
          status: _status(),
          fix: const LocationFixSample(error: 'no_fix'),
        ),
        store: store,
        now: () => start,
      ).refresh();
      expect(state.location.availability, CapabilityAvailability.stale);
      expect(state.location.value?.observedAt, isNot(start));
      expect(state.lastKnownLocation.availability, CapabilityAvailability.available);
      expect(state.freshnessAt(start), DataFreshness.stale);
    });

    test('a future stored timestamp is discarded, not rewritten', () async {
      final store = _MemoryStore()
        ..fix = LocationFix(
          coordinate: const Coordinate(latitude: 31.9, longitude: 35.2),
          observedAt: start.add(const Duration(days: 1)),
        );
      final collector = _collector(
        gateway: _FakeGateway(status: _status(permission: 'denied')),
        store: store,
        now: () => start,
      );
      final state = await collector.refresh();
      expect(state.lastKnownLocation.value, isNull);
    });

    test('storage failures degrade to no history', () async {
      final collector = _collector(
        gateway: _FakeGateway(
          status: _status(),
          fix: _fix(latitude: 31.9, longitude: 35.2),
        ),
        store: _ThrowingStore(),
        now: () => start,
      );
      final state = await collector.refresh();
      expect(state.location.availability, CapabilityAvailability.available);
    });
  });

  group('home location, distance and presence', () {
    const home = HomeLocation(
      coordinate: Coordinate(latitude: 31.9038, longitude: 35.2034),
      radiusKm: 0.2,
    );

    Future<DeviceLocationState> stateWith({
      required HomeLocation? homeLocation,
      required LocationFixSample fix,
      DateTime Function()? now,
      _FakeGateway? gateway,
    }) async {
      final collector = _collector(
        gateway: gateway ?? _FakeGateway(status: _status(), fix: fix),
        now: now ?? () => start,
      );
      collector.setHomeLocation(homeLocation);
      return collector.refresh();
    }

    test('without a home nothing is inferred', () async {
      final state = await stateWith(
        homeLocation: null,
        fix: _fix(latitude: 31.9045, longitude: 35.2034),
      );
      expect(state.homeConfigured, isFalse);
      expect(state.presence, HomePresence.unknown);
      expect(state.distanceFromHome.availability, CapabilityAvailability.unavailable);
      expect(state.distanceFromHome.value, isNull);
    });

    test('inside the radius is at home with a distance', () async {
      final state = await stateWith(
        homeLocation: home,
        fix: _fix(latitude: 31.9045, longitude: 35.2034, accuracy: 18),
      );
      expect(state.presence, HomePresence.atHome);
      expect(state.distanceFromHome.availability, CapabilityAvailability.available);
      expect(state.distanceFromHome.value, lessThan(200));
      expect(state.homeRadiusMeters, 200);
      expect(state.homeEnabled, isTrue);
    });

    test('outside the radius is away from home', () async {
      final state = await stateWith(
        homeLocation: home,
        fix: _fix(latitude: 31.9096, longitude: 35.2034),
      );
      expect(state.presence, HomePresence.awayFromHome);
      expect(state.distanceFromHome.value, greaterThan(200));
    });

    test('a disabled home produces no statement at all', () async {
      final state = await stateWith(
        homeLocation: home.copyWith(enabled: false),
        fix: _fix(latitude: 31.9045, longitude: 35.2034),
      );
      expect(state.homeConfigured, isTrue);
      expect(state.homeEnabled, isFalse);
      expect(state.presence, HomePresence.unknown);
      expect(state.distanceFromHome.availability, CapabilityAvailability.unavailable);
    });

    test('an invalid home coordinate cannot classify anything', () async {
      final state = await stateWith(
        homeLocation: const HomeLocation(
          coordinate: Coordinate(latitude: 91, longitude: 0),
        ),
        fix: _fix(latitude: 31.9045, longitude: 35.2034),
      );
      expect(state.presence, HomePresence.unknown);
    });

    test('an unavailable location never becomes away from home', () async {
      final state = await stateWith(
        homeLocation: home,
        fix: const LocationFixSample(error: 'timeout'),
      );
      expect(state.presence, HomePresence.unknown);
      expect(state.distanceFromHome.value, isNull);
    });

    test('a stale fix yields a stale presence, not at home or away', () async {
      final store = _MemoryStore()
        ..fix = LocationFix(
          coordinate: const Coordinate(latitude: 31.9045, longitude: 35.2034),
          observedAt: start.subtract(const Duration(hours: 3)),
          accuracyMeters: 20,
        );
      final collector = _collector(
        gateway: _FakeGateway(status: _status(permission: 'denied')),
        store: store,
        now: () => start,
      );
      collector.setHomeLocation(home);
      final state = await collector.refresh();

      expect(state.presence, HomePresence.stale);
      expect(state.distanceFromHome.availability, CapabilityAvailability.stale);
      // The distance is still available to a caller who understands the age.
      expect(state.distanceFromHome.value, isNotNull);
      expect(state.distanceFromHome.observedAt, isNot(start));
    });

    test('changing home recalculates without inventing movement', () async {
      final collector = _collector(
        gateway: _FakeGateway(
          status: _status(),
          fix: _fix(latitude: 31.9045, longitude: 35.2034),
        ),
        now: () => start,
      );
      collector.setHomeLocation(home);
      final before = await collector.refresh();
      final fixTime = before.location.observedAt;

      collector.setHomeLocation(
        const HomeLocation(
          coordinate: Coordinate(latitude: 31.9038, longitude: 35.2034),
          radiusKm: 2,
        ),
      );
      final after = collector.current;

      expect(after.presence, HomePresence.atHome);
      expect(after.homeRadiusMeters, 2000);
      // No observation timestamp changed: a configuration change is not a fix.
      expect(after.location.observedAt, fixTime);
      expect(after.lastKnownLocation.value?.observedAt, fixTime);
    });

    test('removing home returns to unknown', () async {
      final collector = _collector(
        gateway: _FakeGateway(
          status: _status(),
          fix: _fix(latitude: 31.9045, longitude: 35.2034),
        ),
        now: () => start,
      );
      collector.setHomeLocation(home);
      await collector.refresh();
      collector.setHomeLocation(null);
      expect(collector.current.presence, HomePresence.unknown);
      expect(collector.current.homeConfigured, isFalse);
    });

    test('unsupported platforms report unsupported presence', () async {
      final collector = _collector(
        gateway: _FakeGateway(status: _status(), platformName: 'unknown'),
        now: () => start,
      );
      collector.setHomeLocation(home);
      final state = await collector.refresh();
      expect(state.presence, HomePresence.unsupported);
    });
  });

  group('error isolation and serialization', () {
    test('a location failure does not break battery or activity', () async {
      final battery = BatteryChargingCollector(
        gateway: _FakeBatteryGateway(
          const BatteryPlatformSample(
            percentage: 55,
            chargingState: 'charging',
            chargingSource: 'usb',
            chargingSourceSupported: true,
          ),
        ),
        now: () => start,
      );
      final activity = ActivityStateCollector(
        gateway: _FakeActivityGateway(),
        store: _NoopActivityStore(),
        now: () => start,
      );
      final location = _collector(
        gateway: _FakeGateway(status: _status())..statusException = StateError('location'),
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
        locationCollector: location,
      );

      final snapshot = await provider.getCurrentState();
      expect(snapshot.battery?.percentage.value, 55);
      expect(snapshot.activity, isNotNull);
      expect(snapshot.location?.location.availability, CapabilityAvailability.error);
      expect(snapshot.availability, isNotNull);
    });

    test('location survives a snapshot round-trip', () async {
      final collector = _collector(
        gateway: _FakeGateway(
          status: _status(),
          fix: _fix(latitude: 31.9045, longitude: 35.2034, accuracy: 18),
        ),
        now: () => start,
      );
      collector.setHomeLocation(
        const HomeLocation(
          coordinate: Coordinate(latitude: 31.9038, longitude: 35.2034),
          radiusKm: 0.2,
        ),
      );
      final state = await collector.refresh();
      final restored = DeviceLocationState.fromJson(state.toJson());

      expect(restored.location.availability, CapabilityAvailability.available);
      expect(restored.location.value?.coordinate.latitude, 31.9045);
      expect(restored.location.value?.accuracyMeters, 18);
      expect(restored.permission.value, DevicePermissionState.granted);
      expect(restored.serviceState, LocationServiceState.enabled);
      expect(restored.presence, HomePresence.atHome);
      expect(restored.distanceFromHome.value, state.distanceFromHome.value);
      expect(restored.homeConfigured, isTrue);
      expect(restored.homeEnabled, isTrue);
      expect(restored.homeRadiusMeters, 200);

      final snapshot = DeviceStateSnapshot(
        deviceId: 'device',
        collectedAt: start,
        capabilities: const {},
        location: state,
      );
      final restoredSnapshot = DeviceStateSnapshot.fromJson(snapshot.toJson());
      expect(restoredSnapshot.location?.presence, HomePresence.atHome);
      expect(
        restoredSnapshot.location?.lastKnownLocation.value?.coordinate.longitude,
        35.2034,
      );
    });

    test('permission-denied state serializes without coordinates', () async {
      final state = await _collector(
        gateway: _FakeGateway(status: _status(permission: 'denied')),
        now: () => start,
      ).refresh();
      final json = state.toJson();
      expect(json['location'], isA<Map<String, Object?>>());
      expect(json.toString(), isNot(contains('latitude')));
      final restored = DeviceLocationState.fromJson(json);
      expect(restored.location.value, isNull);
      expect(restored.presence, HomePresence.unknown);
    });
  });

  group('event monitoring', () {
    test('subscribes only when permission and the service allow it', () async {
      final denied = _collector(
        gateway: _FakeGateway(status: _status(permission: 'denied')),
        now: () => start,
      );
      await denied.start();
      expect(denied.isStarted, isFalse);

      final grantedGateway = _FakeGateway(status: _status());
      final granted = _collector(gateway: grantedGateway, now: () => start);
      await granted.start();
      expect(granted.isStarted, isTrue);
      expect(grantedGateway.events.hasListener, isTrue);

      grantedGateway.emit(_fix(latitude: 31.901, longitude: 35.2));
      await Future<void>.delayed(Duration.zero);
      expect(granted.current.location.value?.coordinate.latitude, 31.901);

      await granted.stop();
      expect(granted.isStarted, isFalse);
      expect(grantedGateway.events.hasListener, isFalse);
    });

    test('a revoked permission cancels native updates', () async {
      final gateway = _FakeGateway(status: _status());
      final collector = _collector(gateway: gateway, now: () => start);
      await collector.start();
      expect(collector.isStarted, isTrue);

      gateway.status = _status(permission: 'denied');
      await collector.refresh();
      expect(collector.isStarted, isFalse);
    });
  });
}

LocationStatusSample _status({
  String permission = 'granted',
  bool precise = true,
  bool serviceEnabled = true,
}) => LocationStatusSample(
  supported: true,
  permission: permission,
  precise: precise,
  serviceEnabled: serviceEnabled,
);

LocationFixSample _fix({
  required double latitude,
  required double longitude,
  double? accuracy = 15,
  DateTime? observedAt,
  bool approximate = false,
}) => LocationFixSample(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: accuracy,
  observedAt: observedAt,
  approximate: approximate,
);

LocationStateCollector _collector({
  required LocationPlatformGateway gateway,
  LocationObservationStore? store,
  DateTime Function()? now,
}) => LocationStateCollector(
  gateway: gateway,
  store: store ?? _MemoryStore(),
  now: now ?? DateTime.now,
);

class _FakeGateway implements LocationPlatformGateway {
  _FakeGateway({
    required this.status,
    this.fix,
    this.platformName = 'android',
  });

  LocationStatusSample status;
  LocationFixSample? fix;
  Object? statusException;
  Object? fixException;
  int statusReads = 0;
  int fixReads = 0;
  int permissionRequests = 0;
  final events = StreamController<Object?>.broadcast();

  @override
  final String platformName;

  @override
  Future<Object?> readStatus() async {
    statusReads++;
    final error = statusException;
    if (error != null) throw error;
    return status;
  }

  @override
  Future<Object?> requestPermission() async {
    permissionRequests++;
    final error = statusException;
    if (error != null) throw error;
    return status;
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<Object?> readCurrentLocation() async {
    fixReads++;
    final error = fixException;
    if (error != null) throw error;
    return fix ?? const LocationFixSample(error: 'no_fix');
  }

  @override
  Stream<Object?> watchChanges() => events.stream;

  void emit(LocationFixSample value) {
    fix = value;
    events.add(value);
  }
}

class _MemoryStore implements LocationObservationStore {
  LocationFix? fix;
  int writes = 0;

  @override
  Future<LocationFix?> readLastKnownFix() async => fix;

  @override
  Future<void> writeLastKnownFix(LocationFix value) async {
    fix = value;
    writes++;
  }
}

class _ThrowingStore implements LocationObservationStore {
  @override
  Future<LocationFix?> readLastKnownFix() async =>
      throw StateError('storage unavailable');

  @override
  Future<void> writeLastKnownFix(LocationFix value) async =>
      throw StateError('storage unavailable');
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

class _FakeActivityGateway implements ActivityPlatformGateway {
  @override
  String get platformName => 'nonAndroid';
  @override
  Future<Object?> readCurrent() async => const ActivityPlatformSample(
    screenStateSupported: false,
  );
  @override
  Stream<Object?> watchChanges() => const Stream.empty();
}

class _NoopActivityStore implements ActivityObservationStore {
  @override
  Future<DateTime?> readLastObservedActivityAt() async => null;

  @override
  Future<void> writeLastObservedActivityAt(DateTime value) async {}
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
