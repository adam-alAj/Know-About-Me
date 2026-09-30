import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/domain/models/battery_state.dart';
import 'package:kam/features/device_state/domain/models/device_location_state.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/services/device_state_sanitizer.dart';
import 'package:kam/features/device_state/domain/services/remote_device_state_parser.dart';
import 'package:kam/features/location/domain/models/location_state.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';

/// Round trip of the three derived flows through their sanitizer and parser:
/// coordinates (location), charging duration, and at-home / away presence.
///
/// The document travels through Firestore Security Rules in between, but the
/// rules enforce the same category gates and value checks (see
/// `firebase/test/firestore.rules.test.js`), so this test proves the client
/// side writes exactly what the rules accept and the reader understands what
/// the writer published.
void main() {
  final observedAt = DateTime.utc(2026, 9, 30, 9, 30);
  const now = '2026-09-30T10:00:00.000Z';

  final sanitizer = DeviceStateSanitizer(
    now: () => DateTime.utc(2026, 9, 30, 10),
  );
  const parser = RemoteDeviceStateParser();

  DeviceStateSnapshot snapshot({
    BatteryState? battery,
    DeviceLocationState? location,
  }) => DeviceStateSnapshot(
    deviceId: 'device-1',
    userId: 'owner-1',
    collectedAt: observedAt,
    capabilities: const <DeviceMetric, StateObservation<Object?>>{},
    battery: battery,
    location: location,
  );

  BatteryState chargingBattery({
    Duration duration = const Duration(hours: 2, minutes: 15),
    DateTime? startedAt,
  }) => BatteryState(
    percentage: StateObservation<int>(
      availability: CapabilityAvailability.available,
      value: 71,
      observedAt: observedAt,
    ),
    chargingState: const StateObservation<BatteryChargingState>(
      availability: CapabilityAvailability.available,
      value: BatteryChargingState.charging,
    ),
    chargingDuration: StateObservation<Duration>(
      availability: CapabilityAvailability.available,
      value: duration,
      observedAt: observedAt,
    ),
    chargingSource: const StateObservation<BatteryChargingSource>(
      availability: CapabilityAvailability.unsupported,
    ),
    chargingStartedAt: startedAt,
  );

  DeviceLocationState locationState({
    required double metersFromHome,
    required HomePresence presence,
    double latitude = 52.517,
    double longitude = 13.412,
  }) => DeviceLocationState(
    location: StateObservation<LocationFix>(
      availability: CapabilityAvailability.available,
      value: LocationFix(
        coordinate: Coordinate(latitude: latitude, longitude: longitude),
        observedAt: observedAt,
        accuracyMeters: 18,
      ),
      observedAt: observedAt,
    ),
    lastKnownLocation: StateObservation<LocationFix>(
      availability: CapabilityAvailability.available,
      value: LocationFix(
        coordinate: Coordinate(latitude: latitude, longitude: longitude),
        observedAt: observedAt,
      ),
      observedAt: observedAt,
    ),
    permission: const StateObservation<DevicePermissionState>(
      availability: CapabilityAvailability.available,
      value: DevicePermissionState.granted,
    ),
    serviceState: LocationServiceState.enabled,
    distanceFromHome: StateObservation<double>(
      availability: CapabilityAvailability.available,
      value: metersFromHome,
      observedAt: observedAt,
    ),
    presence: presence,
    homeConfigured: true,
    homeEnabled: true,
    homeRadiusMeters: 200,
  );

  RemoteStateDocument document(Map<String, Object?> fields) =>
      RemoteStateDocument(
        data: fields,
        receivedAt: DateTime.utc(2026, 9, 30, 10),
        isFromCache: false,
      );

  group('charging duration', () {
    test('travels from an observed duration to a parsed observation', () {
      final payload = sanitizer.sanitizeDeviceState(
        snapshot: snapshot(battery: chargingBattery()),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.battery, SharingCategory.charging},
        sharingPaused: false,
        stateVersion: 4,
      );

      expect(payload.fields['chargingDurationSeconds'], 8100);
      expect(payload.fields['isCharging'], isTrue);
      expect(payload.fields['chargingStartedAt'], isNull);

      final state = parser.parseDeviceState(
        pairId: 'pair-1',
        expectedOwnerUserId: 'owner-1',
        document: document({
          ...payload.fields,
          'updatedAt': DateTime.utc(2026, 9, 30, 10),
        }),
      );

      final observation = state!.observation(DeviceMetric.chargingDuration);
      expect(observation.availability, CapabilityAvailability.available);
      expect(observation.value, const Duration(hours: 2, minutes: 15));
    });

    test('a charging session start time survives and orders the observation', () {
      final startedAt = DateTime.utc(2026, 9, 30, 7, 45);
      final payload = sanitizer.sanitizeDeviceState(
        snapshot: snapshot(
          battery: chargingBattery(startedAt: startedAt),
        ),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.charging},
        sharingPaused: false,
        stateVersion: 1,
      );
      expect(payload.fields['chargingStartedAt'], startedAt);

      final state = parser.parseDeviceState(
        pairId: 'pair-1',
        expectedOwnerUserId: 'owner-1',
        document: document({
          ...payload.fields,
          'updatedAt': DateTime.utc(2026, 9, 30, 10),
        }),
      );
      expect(state!.chargingStartedAt, startedAt);
      expect(
        state.observation(DeviceMetric.chargingDuration).observedAt,
        startedAt,
      );
    });

    test('is withheld from the document when charging is not shared', () {
      final payload = sanitizer.sanitizeDeviceState(
        snapshot: snapshot(battery: chargingBattery()),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
        stateVersion: 1,
      );

      expect(payload.fields.containsKey('chargingDurationSeconds'), isFalse);
      expect(payload.fields.containsKey('isCharging'), isFalse);
      // The battery value itself is still published.
      expect(payload.fields['batteryPercentage'], 71);
      // And the previously shared charging fields are actively retracted.
      expect(
        payload.clearedFields,
        containsAll(['chargingDurationSeconds', 'isCharging']),
      );
    });

    test('a paused owner publishes no state document at all', () {
      final payload = sanitizer.sanitizeDeviceState(
        snapshot: snapshot(battery: chargingBattery()),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.battery, SharingCategory.charging},
        sharingPaused: true,
        stateVersion: 1,
      );

      expect(payload.shareable, isFalse);
      expect(payload.retract, isTrue);
    });

    test('a negative or unobservable duration is never published', () {
      final payload = sanitizer.sanitizeDeviceState(
        snapshot: snapshot(
          battery: chargingBattery(
            duration: const Duration(seconds: -30),
          ),
        ),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.charging},
        sharingPaused: false,
        stateVersion: 1,
      );
      expect(payload.fields.containsKey('chargingDurationSeconds'), isFalse);

      final unavailable = sanitizer.sanitizeDeviceState(
        snapshot: snapshot(
          battery: chargingBattery().copyWith(
            chargingDuration: const StateObservation<Duration>(
              availability: CapabilityAvailability.unknown,
            ),
          ),
        ),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.charging},
        sharingPaused: false,
        stateVersion: 1,
      );
      expect(
        unavailable.fields.containsKey('chargingDurationSeconds'),
        isFalse,
      );
    });
  });

  group('location', () {
    test('coordinates and accuracy survive the round trip', () {
      final payload = sanitizer.sanitizeLocation(
        snapshot: snapshot(location: locationState(
          metersFromHome: 740,
          presence: HomePresence.awayFromHome,
        )),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.location},
        sharingPaused: false,
        stateVersion: 2,
      );

      expect(payload.fields['latitude'], 52.517);
      expect(payload.fields['longitude'], 13.412);
      expect(payload.fields['accuracyMeters'], 18);
      expect(payload.fields['approximate'], isFalse);
      expect(payload.fields['observedAt'], observedAt);
      // distanceFromHome is not shared here, so presence stays out.
      expect(payload.fields.containsKey('homePresence'), isFalse);
      expect(
        payload.clearedFields,
        containsAll(['distanceFromHomeKm', 'homePresence']),
      );

      final location = parser.parseLocation(
        expectedOwnerUserId: 'owner-1',
        document: document({
          ...payload.fields,
          'updatedAt': DateTime.utc(2026, 9, 30, 10),
        }),
      );
      expect(location.hasCoordinates, isTrue);
      expect(location.latitude, 52.517);
      expect(location.longitude, 13.412);
      expect(location.accuracyMeters, 18);
      expect(location.presence, isNull);
      expect(location.observedAt, observedAt);
    });

    test('turning location off retracts the whole document', () {
      final payload = sanitizer.sanitizeLocation(
        snapshot: snapshot(location: locationState(
          metersFromHome: 740,
          presence: HomePresence.awayFromHome,
        )),
        ownerUserId: 'owner-1',
        sharedCategories: const <SharingCategory>{},
        sharingPaused: false,
        stateVersion: 3,
      );
      expect(payload.shareable, isFalse);
      expect(payload.retract, isTrue);
    });

    test('pausing retracts the document as well', () {
      final payload = sanitizer.sanitizeLocation(
        snapshot: snapshot(location: locationState(
          metersFromHome: 740,
          presence: HomePresence.atHome,
        )),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.location, SharingCategory.distanceFromHome},
        sharingPaused: true,
        stateVersion: 3,
      );
      expect(payload.retract, isTrue);
    });

    test('an out-of-range coordinate is withheld, not corrected', () {
      final payload = sanitizer.sanitizeLocation(
        snapshot: snapshot(location: locationState(
          metersFromHome: 10,
          presence: HomePresence.atHome,
          latitude: 94.0,
        )),
        ownerUserId: 'owner-1',
        sharedCategories: const {SharingCategory.location},
        sharingPaused: false,
        stateVersion: 1,
      );
      expect(payload.shareable, isFalse);
      expect(payload.retract, isFalse);
    });
  });

  group('at home / away', () {
    test('distance and presence travel together when shared', () {
      for (final (meters, expected) in <(double, HomePresence)>[
        (40, HomePresence.atHome),
        (7400, HomePresence.awayFromHome),
      ]) {
        final payload = sanitizer.sanitizeLocation(
          snapshot: snapshot(location: locationState(
            metersFromHome: meters,
            presence: expected,
          )),
          ownerUserId: 'owner-1',
          sharedCategories: const {
            SharingCategory.location,
            SharingCategory.distanceFromHome,
          },
          sharingPaused: false,
          stateVersion: 1,
        );

        expect(payload.fields['distanceFromHomeKm'], meters / 1000);
        expect(payload.fields['homePresence'], expected.name);

        final location = parser.parseLocation(
          expectedOwnerUserId: 'owner-1',
          document: document({
            ...payload.fields,
            'updatedAt': DateTime.utc(2026, 9, 30, 10),
          }),
        );
        expect(location.presence, expected);
        expect(location.distanceFromHomeKm, meters / 1000);
      }
    });

    test('presence without a usable distance is not published', () {
      // Distance unavailable (no home, permission, ...) ⇒ no statement at all:
      // an unobservable value must not become a confident at-home claim, and
      // any previously published distance must be actively retracted.
      final fix = LocationFix(
        coordinate: const Coordinate(latitude: 52.517, longitude: 13.412),
        observedAt: observedAt,
      );
      final payload = sanitizer.sanitizeLocation(
        snapshot: snapshot(location: DeviceLocationState(
          location: StateObservation<LocationFix>(
            availability: CapabilityAvailability.available,
            value: fix,
            observedAt: observedAt,
          ),
          lastKnownLocation: const StateObservation<LocationFix>(
            availability: CapabilityAvailability.unknown,
          ),
          permission: const StateObservation<DevicePermissionState>(
            availability: CapabilityAvailability.available,
            value: DevicePermissionState.granted,
          ),
          serviceState: LocationServiceState.enabled,
          distanceFromHome: const StateObservation<double>(
            availability: CapabilityAvailability.unavailable,
          ),
          presence: HomePresence.unknown,
        )),
        ownerUserId: 'owner-1',
        sharedCategories: const {
          SharingCategory.location,
          SharingCategory.distanceFromHome,
        },
        sharingPaused: false,
        stateVersion: 1,
      );

      expect(payload.fields.containsKey('distanceFromHomeKm'), isFalse);
      expect(payload.fields.containsKey('homePresence'), isFalse);
      expect(
        payload.clearedFields,
        containsAll(['distanceFromHomeKm', 'homePresence']),
      );
    });

    test('an unrecognized presence string parses to null, never a guess', () {
      final location = parser.parseLocation(
        expectedOwnerUserId: 'owner-1',
        document: document({
          'ownerUserId': 'owner-1',
          'schemaVersion': 1,
          'latitude': 52.517,
          'longitude': 13.412,
          'observedAt': now,
          'distanceFromHomeKm': 0.74,
          'homePresence': 'definitelyHome',
        }),
      );
      expect(location.presence, isNull);
      // The distance itself is still trustworthy.
      expect(location.distanceFromHomeKm, 0.74);
    });
  });
}

extension on BatteryState {
  BatteryState copyWith({
    StateObservation<Duration>? chargingDuration,
  }) => BatteryState(
    percentage: percentage,
    chargingState: chargingState,
    chargingDuration: chargingDuration ?? this.chargingDuration,
    chargingSource: chargingSource,
    chargingStartedAt: chargingStartedAt,
  );
}
