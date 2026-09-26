// Smoke tests proving the application launches, the root widget renders, and
// the navigation shell is valid (SRS Task 14, Task 16).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('application launches and renders the dashboard', (tester) async {
    await pumpTestApp(tester);

    expect(find.text('Reassurance'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('unavailable metrics are rendered as Unknown, not guessed', (
    tester,
  ) async {
    await pumpTestApp(tester);

    // Battery, charging, network and availability each report Unknown because
    // no native collector exists yet (SRS FR-048, constraint 4).
    expect(find.text('Unknown'), findsNWidgets(4));
  });

  testWidgets('partner area shows an empty state rather than fake data', (
    tester,
  ) async {
    await pumpTestApp(tester);

    expect(find.textContaining('No connected partner yet'), findsOneWidget);
  });

  testWidgets('navigates from the dashboard to the privacy branch', (
    tester,
  ) async {
    await pumpTestApp(tester);

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy and sharing'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
  });
}
