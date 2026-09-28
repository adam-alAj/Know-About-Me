import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/rules/domain/rule_draft.dart';

import '../support/rule_test_app.dart';

/// The complete rule lifecycle a user performs (SRS FR-026 – FR-040):
/// create → appears in the list → edit → disable → re-enable → invalid edit is
/// blocked → delete.
void main() {
  const nameKey = ValueKey<String>('rule-name');
  const outputKey = ValueKey<String>('rule-output');
  const probabilityKey = ValueKey<String>('rule-probability');
  const durationValueKey = ValueKey<String>(
    'rule-condition-0-chargingDuration-value',
  );

  /// Lets a success snack bar expire so it cannot intercept a later tap.
  Future<void> settleSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('create, edit, disable, re-enable, reject, delete', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = await pumpAppAtRules(tester);
    const scopeQuery = ('user-a', 'pair-1');

    // --- Create ---------------------------------------------------------
    await openRuleBuilder(tester);
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
    await settleSnackBar(tester);

    expect(find.text('Long Charging'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.textContaining('4 hours'), findsOneWidget);

    var rules = await repository.getRules(
      ownerUserId: scopeQuery.$1,
      pairId: scopeQuery.$2,
    );
    expect(rules, hasLength(1));
    expect(rules.single.version, 1);
    final createdId = rules.single.id;

    // --- Edit: 240 minutes becomes 300 minutes ---------------------------
    // A round number of minutes is shown in hours ("4"), so the edit is made in
    // hours ("5") and the saved canonical value is still 300 minutes.
    await tester.tap(find.text('Long Charging'));
    await tester.pumpAndSettle();
    expect(find.text('Edit rule'), findsOneWidget);
    final loadedThreshold = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(durationValueKey),
        matching: find.byType(EditableText),
      ),
    );
    expect(loadedThreshold.controller.text, '4');

    await tester.enterText(find.byKey(durationValueKey), '5');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    await settleSnackBar(tester);

    rules = await repository.getRules(
      ownerUserId: scopeQuery.$1,
      pairId: scopeQuery.$2,
    );
    expect(
      rules.single.condition.durationThreshold,
      const Duration(minutes: 300),
    );
    expect(
      rules.single.version,
      2,
      reason: 'the version changes, the id does not',
    );
    expect(rules.single.id, createdId);
    expect(find.textContaining('5 hours'), findsOneWidget);

    // --- Disable ---------------------------------------------------------
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Disabled'), findsOneWidget);
    rules = await repository.getRules(
      ownerUserId: scopeQuery.$1,
      pairId: scopeQuery.$2,
    );
    expect(rules, hasLength(1), reason: 'disabling never deletes');
    expect(rules.single.enabled, isFalse);

    // --- Re-enable -------------------------------------------------------
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Enabled'), findsOneWidget);
    rules = await repository.getRules(
      ownerUserId: scopeQuery.$1,
      pairId: scopeQuery.$2,
    );
    expect(rules.single.enabled, isTrue);

    // --- Invalid edit: probability 150% is blocked -----------------------
    await tester.tap(find.text('Long Charging'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(probabilityKey), '150');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Edit rule'), findsOneWidget);
    expect(
      find.text('The user-defined probability must be between 0 and 100.'),
      findsOneWidget,
    );
    rules = await repository.getRules(
      ownerUserId: scopeQuery.$1,
      pairId: scopeQuery.$2,
    );
    expect(rules.single.actions.single.probabilityPercent, 70);
    expect(rules.single.version, 2, reason: 'a rejected save changes nothing');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // --- Delete ----------------------------------------------------------
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete this rule?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Long Charging'), findsNothing);
    expect(find.text('No rules yet'), findsOneWidget);
    expect(
      await repository.getRules(
        ownerUserId: scopeQuery.$1,
        pairId: scopeQuery.$2,
      ),
      isEmpty,
    );
  });
}
