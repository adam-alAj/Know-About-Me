import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/device_location_state.dart';
import 'package:kam/features/device_state/presentation/providers/device_state_providers.dart';
import 'package:kam/features/pairing/presentation/providers/pairing_providers.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('the home location card opens the map picker', (tester) async {
    // A tall viewport keeps the whole privacy page on screen, so the home card
    // is built and tappable without scrolling through an unrelated list.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTestApp(
      tester,
      overrides: [
        partnerScopeProvider.overrideWithValue(
          const AsyncData<PartnerScope?>(null),
        ),
        // The platform location gateway does not exist under `flutter_test`, so
        // the reading is pinned: the screen's own behaviour is what is under
        // test, not the collector's platform handling.
        currentLocalLocationStateProvider.overrideWith(
          (ref) => Stream.value(DeviceLocationState.unknown),
        ),
      ],
    );

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Identify home on map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The map picker was pushed above the privacy page, with a centre-pin map
    // and the confirm/reset actions.
    expect(find.text('Identify home'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Save this as my home'), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
    // OpenStreetMap requires attribution on the tiles it serves.
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    // The picker is a private action, so it says so rather than implying the
    // coordinate is shared.
    expect(find.textContaining('Your home stays private'), findsOneWidget);

    // Map tiles cannot be fetched in a test environment; drain the expected
    // image error instead of letting it fail the test.
    while (tester.takeException() != null) {}
  });
}
