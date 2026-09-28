import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_draft.dart';
import 'package:kam/features/rules/presentation/widgets/rule_condition_editor.dart';

import '../support/rule_test_app.dart';

void main() {
  const nameKey = ValueKey<String>('rule-name');
  const outputKey = ValueKey<String>('rule-output');
  const probabilityKey = ValueKey<String>('rule-probability');
  const durationValueKey = ValueKey<String>(
    'rule-condition-0-chargingDuration-value',
  );

  testWidgets('creates a valid rule and persists it', (tester) async {
    useTallSurface(tester);
    final repository = await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    expect(find.text('New rule'), findsOneWidget);

    await tester.enterText(find.byKey(nameKey), 'Long Charging');
    await tester.enterText(find.byKey(durationValueKey), '240');

    await chooseDropdownOption<RuleOutputKind>(
      tester,
      'User-defined probability',
    );
    await tester.enterText(find.byKey(outputKey), 'may be sleeping');
    await tester.enterText(find.byKey(probabilityKey), '70');

    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();

    final rules = await repository.getRules(
      ownerUserId: 'user-a',
      pairId: 'pair-1',
    );
    expect(rules, hasLength(1));
    final rule = rules.single;
    expect(rule.name, 'Long Charging');
    expect(rule.condition.metric, RuleMetric.chargingDuration);
    expect(rule.condition.durationThreshold, const Duration(hours: 4));
    expect(rule.actions.single.type, RuleActionType.displayProbability);
    expect(rule.actions.single.probabilityPercent, 70);
    expect(rule.enabled, isTrue);
  });

  testWidgets('blocks saving an incomplete rule and explains why', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();

    expect(find.text('New rule'), findsOneWidget);
    expect(find.textContaining('to fix'), findsOneWidget);
    expect(
      await repository.getRules(ownerUserId: 'user-a', pairId: 'pair-1'),
      isEmpty,
    );
  });

  testWidgets('rejects an out-of-range user-defined probability', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    await tester.enterText(find.byKey(nameKey), 'Long Charging');
    await tester.enterText(find.byKey(durationValueKey), '240');
    await chooseDropdownOption<RuleOutputKind>(
      tester,
      'User-defined probability',
    );
    await tester.enterText(find.byKey(outputKey), 'may be sleeping');
    await tester.enterText(find.byKey(probabilityKey), '150');

    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();

    expect(
      find.text('The user-defined probability must be between 0 and 100.'),
      findsOneWidget,
    );
    expect(
      await repository.getRules(ownerUserId: 'user-a', pairId: 'pair-1'),
      isEmpty,
    );
  });

  testWidgets('rejects a non-numeric threshold', (tester) async {
    useTallSurface(tester);
    await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    await tester.enterText(find.byKey(nameKey), 'Long Charging');
    await tester.enterText(find.byKey(outputKey), 'away');
    await tester.enterText(find.byKey(durationValueKey), 'hello');

    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();

    expect(find.textContaining('enter a number'), findsWidgets);
    expect(find.text('New rule'), findsOneWidget);
  });

  testWidgets('allows selecting a state instead of typing a value', (
    tester,
  ) async {
    useTallSurface(tester);
    await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    await tester.enterText(find.byKey(nameKey), 'Charging');
    await tester.enterText(find.byKey(outputKey), 'plugged in');
    await chooseDropdownOption<RuleMetric>(tester, 'Charging');

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rule-condition-0-chargingState-value')),
      findsNothing,
    );

    await chooseDropdownOption<String>(tester, 'Charging');
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();

    expect(find.text('New rule'), findsNothing);
  });

  testWidgets('adds and removes conditions and shows the AND/OR control', (
    tester,
  ) async {
    useTallSurface(tester);
    await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    expect(find.byType(RuleConditionEditor), findsOneWidget);
    expect(find.text('All'), findsNothing);

    await tester.tap(find.text('Add condition'));
    await tester.pumpAndSettle();

    expect(find.byType(RuleConditionEditor), findsNWidgets(2));
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
    await tester.pumpAndSettle();

    expect(find.byType(RuleConditionEditor), findsOneWidget);
  });

  testWidgets('changing the metric swaps the value editor for its type', (
    tester,
  ) async {
    useTallSurface(tester);
    await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    await chooseDropdownOption<RuleMetric>(tester, 'Battery percentage');

    expect(
      find.byKey(
        const ValueKey<String>('rule-condition-0-batteryPercentage-value'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling leaves the repository unchanged', (tester) async {
    useTallSurface(tester);
    final repository = await pumpAppAtRules(tester);
    await openRuleBuilder(tester);

    await tester.enterText(find.byKey(nameKey), 'Discarded');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('No rules yet'), findsOneWidget);
    expect(
      await repository.getRules(ownerUserId: 'user-a', pairId: 'pair-1'),
      isEmpty,
    );
  });
}
