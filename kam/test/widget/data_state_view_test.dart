import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/ui/data_presentation_state.dart';
import 'package:kam/core/ui/data_state_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders a loading indicator', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DataStateView(
          presentation: const DataPresentation.loading(),
          loadedBuilder: (context) => const Text('content'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);
  });

  testWidgets('renders a failure with a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        DataStateView(
          presentation: const DataPresentation.failure(
            'Could not reach the service',
          ),
          onRetry: () => retried = true,
          loadedBuilder: (context) => const Text('content'),
        ),
      ),
    );

    expect(find.text('Could not reach the service'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('renders an empty state distinct from unknown', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DataStateView(
          presentation: const DataPresentation.empty(),
          loadedBuilder: (context) => const Text('content'),
        ),
      ),
    );

    expect(find.text('Nothing here yet.'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets('renders each non-available state with its own label', (
    tester,
  ) async {
    final cases = <DataPresentation, String>{
      const DataPresentation.unknown(): 'Unknown',
      const DataPresentation.unsupported(): 'Not supported on this device',
      const DataPresentation.unavailable(): 'Unavailable',
      const DataPresentation.paused(): 'Sharing paused',
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(
        _wrap(
          DataStateView(
            presentation: entry.key,
            loadedBuilder: (context) => const Text('content'),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      // No fabricated value is ever shown for a non-available state.
      expect(find.text('content'), findsNothing);
    }
  });

  testWidgets('renders loaded content with a stale freshness caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DataStateView(
          presentation: const DataPresentation.loaded(
            freshness: DataFreshness.stale,
            age: Duration(hours: 2, minutes: 13),
          ),
          loadedBuilder: (context) => const Text('42%'),
        ),
      ),
    );

    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Last updated 2h 13m ago'), findsOneWidget);
  });

  testWidgets('renders loaded content without a caption when freshness is '
      'unknown', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DataStateView(
          presentation: const DataPresentation.loaded(),
          loadedBuilder: (context) => const Text('42%'),
        ),
      ),
    );

    expect(find.text('42%'), findsOneWidget);
    expect(find.textContaining('Updated'), findsNothing);
  });
}
