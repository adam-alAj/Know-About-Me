import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/domain/models/battery_state.dart';
import 'package:kam/features/device_state/domain/models/network_state.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/state_observation.dart';
import 'package:kam/features/location/domain/models/location_state.dart';
import 'package:kam/features/rules/domain/partner_state_adapter.dart';

import '../support/rule_test_app.dart';

void main() {
  group('PartnerStateAdapter', () {
    test('carries published battery and charging facts across unchanged', () {
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(
          batteryPercentage: 72,
          chargingState: 'charging',
          chargingDuration: const Duration(hours: 4, minutes: 11),
          chargingStartedAt: testNow.subtract(
            const Duration(hours: 4, minutes: 11),
          ),
        ),
      );

      final battery = snapshot.battery!;
      expect(battery.percentage.availability, CapabilityAvailability.available);
      expect(battery.percentage.value, 72);
      expect(battery.chargingState.value, BatteryChargingState.charging);
      expect(
        battery.chargingDuration.value,
        const Duration(hours: 4, minutes: 11),
      );
      // The duration is stamped with when the partner reported it, not with the
      // session start: otherwise every long charging session would look stale
      // and a "charging for four hours" rule could never fire.
      expect(battery.chargingDuration.observedAt, snapshot.collectedAt);
      // The session start is still preserved, because that is what a time
      // threshold is measured from.
      expect(battery.chargingStartedAt, isNotNull);
      // Charger type is not part of the contract.
      expect(
        battery.chargingSource.availability,
        CapabilityAvailability.unsupported,
      );
    });

    test('normalizes the partner charging flag to the rule vocabulary', () {
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(chargingState: 'discharging'),
      );

      // The wire says "discharging"; the rule catalogue says "Not charging".
      expect(
        snapshot.battery!.chargingState.value,
        BatteryChargingState.notCharging,
      );
      expect(snapshot.battery!.chargingState.value!.name, 'notCharging');
    });

    test('never fabricates a metric the partner did not publish', () {
      final snapshot = PartnerStateAdapter.adapt(testPartnerState());

      expect(
        snapshot.battery!.percentage.availability,
        CapabilityAvailability.unavailable,
      );
      expect(snapshot.battery!.percentage.value, isNull);
      expect(
        snapshot.network!.status.availability,
        CapabilityAvailability.unavailable,
      );
      expect(snapshot.network!.status.value, isNull);
      expect(
        snapshot.activity!.screenState.availability,
        CapabilityAvailability.unavailable,
      );
      // No location document at all is not an invented "away from home".
      expect(snapshot.location, isNull);
      expect(
        snapshot.availability!.availability,
        CapabilityAvailability.unknown,
      );
    });

    test('preserves a non-available partner reason instead of upgrading it',
        () {
      final state = RemoteDeviceState(
        pairId: 'pair-1',
        ownerUserId: 'user-b',
        observations: <DeviceMetric, StateObservation<Object?>>{
          DeviceMetric.screenState: const StateObservation<Object?>(
            availability: CapabilityAvailability.unsupported,
            source: 'partner_sync',
          ),
          DeviceMetric.chargingDuration: const StateObservation<Object?>(
            availability: CapabilityAvailability.permissionDenied,
            source: 'partner_sync',
          ),
        },
        schemaVersion: 1,
        receivedAt: testNow,
        isFromCache: false,
        observedAt: testNow,
      );

      final snapshot = PartnerStateAdapter.adapt(state);
      expect(
        snapshot.activity!.screenState.availability,
        CapabilityAvailability.unsupported,
      );
      expect(
        snapshot.battery!.chargingDuration.availability,
        CapabilityAvailability.permissionDenied,
      );
    });

    test('marks a value-less "available" observation as unknown', () {
      final state = RemoteDeviceState(
        pairId: 'pair-1',
        ownerUserId: 'user-b',
        observations: <DeviceMetric, StateObservation<Object?>>{
          DeviceMetric.batteryPercentage: const StateObservation<Object?>(
            availability: CapabilityAvailability.available,
            source: 'partner_sync',
          ),
        },
        schemaVersion: 1,
        receivedAt: testNow,
        isFromCache: false,
        observedAt: testNow,
      );

      expect(
        PartnerStateAdapter.adapt(state).battery!.percentage.availability,
        CapabilityAvailability.unknown,
      );
    });

    test('rejects a battery percentage outside the observable range', () {
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(batteryPercentage: 240),
      );

      expect(snapshot.battery!.percentage.value, isNull);
      expect(
        snapshot.battery!.percentage.availability,
        CapabilityAvailability.unknown,
      );
    });

    test('maps network status and keeps last-online as the only anchor', () {
      final lastOnline = testNow.subtract(const Duration(minutes: 40));
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(networkStatus: 'offline', lastOnlineAt: lastOnline),
      );

      expect(snapshot.network!.status.value, NetworkOnlineStatus.offline);
      expect(snapshot.network!.lastOnlineAt, lastOnline);
      // Connectivity transport is not synchronized, so it is never guessed.
      expect(
        snapshot.network!.connectivity.availability,
        CapabilityAvailability.unknown,
      );
    });

    test('measures offline duration to the published observation, not to now',
        () {
      final lastOnline = testNow.subtract(const Duration(minutes: 90));
      final observed = testNow.subtract(const Duration(minutes: 20));
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(
          networkStatus: 'offline',
          lastOnlineAt: lastOnline,
          observedAt: observed,
        ),
      );

      final offline = snapshot.network!.offlineDuration;
      expect(offline.value, const Duration(minutes: 70));
      // Freshness is therefore judged against the document's own time, so a
      // rule built on an old document reports stale instead of confident.
      expect(offline.observedAt, observed);
      expect(offline.source, PartnerStateAdapter.derivedSource);
    });

    test('does not derive an offline duration while online', () {
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(
          networkStatus: 'online',
          lastOnlineAt: testNow.subtract(const Duration(minutes: 90)),
        ),
      );

      expect(
        snapshot.network!.offlineDuration.availability,
        CapabilityAvailability.unavailable,
      );
      expect(snapshot.network!.offlineDuration.value, isNull);
    });

    test('converts the shared distance from kilometres to metres', () {
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(
          latitude: 52.1,
          longitude: 4.3,
          distanceFromHomeKm: 7.25,
          presence: HomePresence.awayFromHome,
        ),
      );

      final location = snapshot.location!;
      expect(location.distanceFromHome.value, 7250);
      expect(location.presence, HomePresence.awayFromHome);
      expect(location.location.availability, CapabilityAvailability.available);
      expect(location.location.value!.coordinate.latitude, 52.1);
      expect(location.lastKnownLocation.availability,
          CapabilityAvailability.available);
      // The partner's permission is not synchronized, so it stays unknown
      // rather than being assumed granted.
      expect(
        location.permission.availability,
        CapabilityAvailability.unknown,
      );
    });

    test('keeps coordinates and derived presence separate documents', () {
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(
          latitude: 52.1,
          longitude: 4.3,
          // Distance withheld while the coordinates are shared.
        ),
      );

      final location = snapshot.location!;
      expect(location.location.availability, CapabilityAvailability.available);
      expect(
        location.distanceFromHome.availability,
        CapabilityAvailability.unavailable,
      );
      expect(location.presence, HomePresence.unknown);
      expect(location.homeConfigured, isFalse);
    });

    test('carries availability evidence without ever claiming a power state',
        () {
      final lastOnline = testNow.subtract(const Duration(minutes: 5));
      final snapshot = PartnerStateAdapter.adapt(
        testPartnerState(
          availabilityState: 'available',
          lastOnlineAt: lastOnline,
        ),
      );

      final evidence = snapshot.availability!;
      expect(evidence.availability, CapabilityAvailability.available);
      expect(evidence.lastConfirmedAvailableAt, lastOnline);
      expect(evidence.source, PartnerStateAdapter.carriedSource);
    });
  });
}
