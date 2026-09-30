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

  testWidgets('dashboard includes the local device section', (tester) async {
    await pumpTestApp(tester);

    // The user-facing device summary is rendered in the lower section of the
    // dashboard. Its platform-specific state can be Unavailable or Unsupported
    // rather than a misleading default.
    final observationHeading = find.text('Screen and activity');
    final dashboardList = find.byType(ListView).first;
    for (
      var attempt = 0;
      attempt < 12 && observationHeading.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(dashboardList, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(observationHeading, findsOneWidget);
  });

  testWidgets('partner area states the truth rather than showing fake data', (
    tester,
  ) async {
    await pumpTestApp(tester);

    // This build has no Firebase and no pair, so the honest statement is that
    // there is no active connection — not an invented partner value.
    final partnerStatus = find.text('No active connection');
    await tester.scrollUntilVisible(
      partnerStatus,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(partnerStatus, findsOneWidget);
    // Without a data source, no partner values may be invented.
    expect(find.textContaining('Partner device'), findsNothing);
  });

  testWidgets('navigates from the dashboard to the privacy branch', (
    tester,
  ) async {
    await pumpTestApp(tester);

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy and sharing'), findsOneWidget);
    expect(
      find.text('No active connection. Nothing is shared.'),
      findsOneWidget,
    );
  });
}
