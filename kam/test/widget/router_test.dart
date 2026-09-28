import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/history/domain/models/device_event.dart';
import 'package:kam/features/history/domain/repositories/history_repository.dart';
import 'package:kam/features/history/presentation/history_providers.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('starts on the dashboard inside the navigation shell', (
    tester,
  ) async {
    await pumpTestApp(tester);

    expect(find.text('Reassurance'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Rules'), findsOneWidget); // navigation label only
  });

  testWidgets('navigates between shell branches', (tester) async {
    await pumpTestApp(
      tester,
      overrides: [
        localHistoryRepositoryProvider.overrideWithValue(
          _EmptyHistoryRepository(),
        ),
      ],
    );

    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    // Phase 14 replaced the placeholder with rule management. Without an active
    // connection there is nothing to manage yet, so the screen states that
    // honestly instead of offering a rule that could not be saved.
    expect(find.text('No connection yet'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No events yet'), findsOneWidget);

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy and sharing'), findsOneWidget);
  });

  testWidgets('pushes the profile route above the shell', (tester) async {
    await pumpTestApp(tester);

    await openProfile(tester);

    expect(find.text('Profile'), findsOneWidget);
    // A signed-in user's own account details, from the authentication state.
    expect(find.text('afraa@example.com'), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);
  });

  testWidgets('renders a not-found screen for an unknown route', (
    tester,
  ) async {
    await pumpTestApp(tester, initialLocation: '/does-not-exist');

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.textContaining('does-not-exist'), findsOneWidget);
  });

  testWidgets('unknown route can navigate back to the dashboard', (
    tester,
  ) async {
    await pumpTestApp(tester, initialLocation: '/does-not-exist');

    await tester.tap(find.text('Back to reassurance'));
    await tester.pumpAndSettle();

    expect(find.text('Reassurance'), findsOneWidget);
  });
}

class _EmptyHistoryRepository implements HistoryRepository {
  @override
  Future<void> add(DeviceEvent event) async {}

  @override
  Future<List<DeviceEvent>> page({
    EventCategory? category,
    int limit = 50,
    DateTime? before,
  }) async => const <DeviceEvent>[];

  @override
  Future<void> clearLocal() async {}
}
