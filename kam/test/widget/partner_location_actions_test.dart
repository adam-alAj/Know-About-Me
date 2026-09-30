import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/state_observation.dart';
import 'package:kam/features/device_state/domain/sources/map_launcher.dart';
import 'package:kam/features/device_state/presentation/providers/device_state_providers.dart';
import 'package:kam/features/device_state/presentation/widgets/partner_location_actions.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1, 12);

  Future<void> pump(
    WidgetTester tester, {
    required RemoteLocationState location,
    required _FakeMapLauncher launcher,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [mapLauncherProvider.overrideWithValue(launcher)],
        child: MaterialApp(
          home: Scaffold(
            body: PartnerLocationActions(location: location, now: now),
          ),
        ),
      ),
    );
  }

  RemoteLocationState locationAt(DateTime observedAt) => RemoteLocationState(
    availability: CapabilityAvailability.available,
    latitude: 52.52,
    longitude: 13.405,
    observedAt: observedAt,
  );

  testWidgets('a fresh authorized coordinate offers Google Maps', (
    tester,
  ) async {
    final launcher = _FakeMapLauncher();
    await pump(
      tester,
      location: locationAt(now.subtract(const Duration(minutes: 2))),
      launcher: launcher,
    );

    expect(find.text('Open in Google Maps'), findsOneWidget);
    expect(
      find.text('This is the last known location, not a current position.'),
      findsNothing,
    );

    await tester.tap(find.text('Open in Google Maps'));
    await tester.pumpAndSettle();
    expect(launcher.calls, 1);
    expect(launcher.lastLatitude, 52.52);
    expect(launcher.lastLongitude, 13.405);
  });

  testWidgets('a stale coordinate is labelled as the last known location', (
    tester,
  ) async {
    final launcher = _FakeMapLauncher();
    await pump(
      tester,
      location: locationAt(now.subtract(const Duration(hours: 2))),
      launcher: launcher,
    );

    expect(find.text('Open last known location'), findsOneWidget);
    expect(
      find.text('This is the last known location, not a current position.'),
      findsOneWidget,
    );
  });

  testWidgets('no action is offered without usable coordinates', (
    tester,
  ) async {
    final launcher = _FakeMapLauncher();
    await pump(
      tester,
      location: const RemoteLocationState(
        availability: CapabilityAvailability.unavailable,
      ),
      launcher: launcher,
    );

    expect(find.text('Open in Google Maps'), findsNothing);
    expect(find.text('Open last known location'), findsNothing);
    expect(launcher.calls, 0);
  });

  testWidgets('a failure to open is reported instead of silently ignored', (
    tester,
  ) async {
    final launcher = _FakeMapLauncher()..result = false;
    await pump(tester, location: locationAt(now), launcher: launcher);

    await tester.tap(find.text('Open in Google Maps'));
    await tester.pumpAndSettle();

    expect(
      find.text('No map application is available to open this location.'),
      findsOneWidget,
    );
  });
}

class _FakeMapLauncher implements MapLauncher {
  int calls = 0;
  bool result = true;
  double? lastLatitude;
  double? lastLongitude;

  @override
  String get platformName => 'android';

  @override
  bool get isSupported => true;

  @override
  Future<bool> openCoordinates({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    calls++;
    lastLatitude = latitude;
    lastLongitude = longitude;
    return result;
  }
}
