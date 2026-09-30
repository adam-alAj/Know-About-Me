import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/device_location_state.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/domain/models/state_observation.dart';
import 'package:kam/features/device_state/presentation/providers/device_state_providers.dart';
import 'package:kam/features/device_state/presentation/providers/sync_providers.dart';
import 'package:kam/features/location/domain/models/location_state.dart';
import 'package:kam/features/pairing/presentation/providers/pairing_providers.dart';

import '../fakes/fake_profile_repository.dart';
import '../support/test_app.dart';

void main() {
  const scope = PartnerScope(pairId: 'pair-a', partnerUserId: 'user-b');

  testWidgets(
    'sharing controls stay read-only when settings cannot be confirmed',
    (tester) async {
      final sharingController = StreamController<PairSharingState>();
      await pumpTestApp(
        tester,
        overrides: [
          partnerScopeProvider.overrideWithValue(const AsyncData(scope)),
          ownSharingProvider.overrideWith((ref) => sharingController.stream),
        ],
      );
      await tester.tap(find.text('Privacy'));
      // The initial privacy state intentionally shows an indeterminate loader,
      // so pump a bounded transition interval instead of waiting for animations
      // to settle forever.
      await tester.pump(const Duration(milliseconds: 500));
      sharingController.addError(StateError('unavailable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(
        find.text(
          'Settings are read-only until your current sharing choices can be confirmed.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sharing settings could not be confirmed'),
        findsOneWidget,
      );
      final toggles = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(toggles, isNotEmpty);
      expect(toggles.every((toggle) => toggle.onChanged == null), isTrue);
      await sharingController.close();
    },
  );

  testWidgets('confirmed privacy settings expose labelled controls', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      overrides: [
        partnerScopeProvider.overrideWithValue(const AsyncData(scope)),
        ownSharingProvider.overrideWith(
          (ref) => Stream.value(
            const PairSharingState(paused: false, categories: {}),
          ),
        ),
      ],
    );
    await tester.tap(find.text('Privacy'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('What you share'), findsOneWidget);
    expect(find.text('Pause all sharing'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    final toggles = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(toggles.every((toggle) => toggle.onChanged != null), isTrue);
  });

  testWidgets('the home location is private and configurable without a pair', (
    tester,
  ) async {
    final profiles = FakeProfileRepository();
    final observedAt = DateTime.utc(2026, 10, 1, 9);
    final fixWithTime = LocationFix(
      coordinate: const Coordinate(latitude: 1.25, longitude: 2.5),
      observedAt: observedAt,
    );
    final locationState = DeviceLocationState(
      location: StateObservation<LocationFix>(
        availability: CapabilityAvailability.available,
        value: fixWithTime,
        observedAt: observedAt,
      ),
      lastKnownLocation: StateObservation<LocationFix>(
        availability: CapabilityAvailability.available,
        value: fixWithTime,
        observedAt: observedAt,
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
    );

    await pumpTestApp(
      tester,
      profileRepository: profiles,
      overrides: [
        currentLocalLocationStateProvider.overrideWith(
          (ref) => Stream.value(locationState),
        ),
      ],
    );
    await tester.tap(find.text('Privacy'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Home location'), findsOneWidget);
    expect(find.text('Status: Not configured'), findsOneWidget);

    await tester.tap(find.text('Set home location'));
    await tester.pumpAndSettle();

    final stored = profiles.preferences.homeLocation;
    expect(stored, isNotNull);
    expect(stored!.coordinate.latitude, 1.25);
    expect(stored.coordinate.longitude, 2.5);
    // The home coordinates are stored privately and are never written into a
    // shared document here.
    expect(find.textContaining('1.25'), findsNothing);
  });
}
