import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/rule_test_app.dart';

void main() {
  testWidgets('explains that a connection is needed before rules', (
    tester,
  ) async {
    await pumpAppAtRules(tester, hasScope: false);

    expect(find.text('No connection yet'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('shows a calm empty state with a create action', (tester) async {
    await pumpAppAtRules(tester);

    expect(find.text('No rules yet'), findsOneWidget);
    expect(find.text('Create rule'), findsWidgets);
  });

  testWidgets('lists a rule with its state, conditions and interpretation', (
    tester,
  ) async {
    await pumpAppAtRules(tester, seed: [testRule()]);

    expect(find.text('Long Charging'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Charging duration is at least 4 hours'), findsOneWidget);
    expect(find.text('Status: Away from home'), findsOneWidget);
  });

  testWidgets('shows a disabled rule as disabled', (tester) async {
    await pumpAppAtRules(tester, seed: [testRule(enabled: false)]);

    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Enabled'), findsNothing);
  });

  testWidgets('disabling a rule keeps it, it is not deleted', (tester) async {
    final repository = await pumpAppAtRules(tester, seed: [testRule()]);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Disabled'), findsOneWidget);
    final rules = await repository.getRules(
      ownerUserId: 'user-a',
      pairId: 'pair-1',
    );
    expect(rules, hasLength(1));
    expect(rules.single.enabled, isFalse);
  });

  testWidgets('deleting a rule requires confirmation that names the rule', (
    tester,
  ) async {
    final repository = await pumpAppAtRules(tester, seed: [testRule()]);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete this rule?'), findsOneWidget);
    expect(find.textContaining('Long Charging'), findsWidgets);

    // Cancelling leaves the rule untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Long Charging'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Long Charging'), findsNothing);
    expect(find.text('No rules yet'), findsOneWidget);
    expect(
      await repository.getRules(ownerUserId: 'user-a', pairId: 'pair-1'),
      isEmpty,
    );
  });
}
