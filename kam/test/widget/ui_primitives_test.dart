import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/ui/widgets/section_card.dart';
import 'package:kam/core/ui/widgets/skeleton.dart';
import 'package:kam/core/ui/widgets/status_pill.dart';

/// The shared presentation primitives must carry their meaning in text and
/// semantics, never in colour alone (SRS NFR-028), and a loading state must keep
/// its section heading so the layout does not shift.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  testWidgets('a status pill states its meaning in text and semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const StatusPill(
        label: 'Offline',
        icon: Icons.cloud_off_outlined,
        tone: StatusTone.attention,
      ),
    );

    expect(find.text('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    // Colour is reinforcement only: the words alone carry the meaning.
    expect(tester.getSemantics(find.byType(StatusPill)).label, 'Offline');
    handle.dispose();
  });

  testWidgets('a state row announces its label with its value', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const StateRow(
        label: 'Screen',
        value: 'Off',
        emphasis: StateRowEmphasis.strong,
      ),
    );

    expect(find.text('Screen'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(StateRow)).label,
      'Screen: Off',
    );
    handle.dispose();
  });

  testWidgets('a section keeps its heading while it loads', (tester) async {
    await pump(
      tester,
      const SectionSkeleton(
        title: 'Screen and activity',
        icon: Icons.phone_android_outlined,
        rows: 2,
      ),
    );

    // The heading is real, not a placeholder: the user can see what the section
    // is, and the layout will not jump when the value arrives.
    expect(find.text('Screen and activity'), findsOneWidget);
  });

  testWidgets('status tones resolve to distinct accessible colours', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B6E8F));
    final pairs = StatusTone.values
        .map((tone) => StatusPill.colorsFor(scheme, tone))
        .toList();
    // Each tone has its own pair, so two different states can never look the
    // same.
    final backgrounds = pairs.map((pair) => pair.$2).toSet();
    expect(backgrounds.length, StatusTone.values.length);
    for (final (foreground, background) in pairs) {
      expect(foreground, isNot(background));
    }
  });
}
