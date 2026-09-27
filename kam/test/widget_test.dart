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

    // Availability is still an unsupported legacy metric. Battery and network
    // status are presented by their local collectors below.
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('partner area shows an empty state rather than fake data', (
    tester,
  ) async {
    await pumpTestApp(tester);

    // The dashboard now carries the Phase 9 activity card, so the partner
    // section sits below the initial viewport of the ListView.
    final partnerEmptyState = find.textContaining(
      'No partner device data is available yet.',
    );
    await tester.scrollUntilVisible(
      partnerEmptyState,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(partnerEmptyState, findsOneWidget);
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
