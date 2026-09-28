import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/rules/domain/models/interpretation_result.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_draft.dart';
import 'package:kam/features/rules/domain/rule_evaluation_service.dart';
import 'package:kam/features/rules/presentation/widgets/interpretation_type_badge.dart';
import 'package:kam/features/rules/presentation/widgets/rule_interpretation_card.dart';

import '../support/rule_test_app.dart';

void main() {
  const service = RuleEvaluationService();

  Rule rule({
    String name = 'Long Charging',
    RuleOutputKind output = RuleOutputKind.probability,
    String outputText = 'Possible sleep period',
    int? probability = 70,
    bool allowStaleData = false,
    RuleCondition? condition,
  }) => Rule(
    id: 'rule-1',
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    name: name,
    condition:
        condition ??
        const RuleCondition(
          metric: RuleMetric.chargingDuration,
          operator: RuleOperator.greaterThanOrEqual,
          durationThreshold: Duration(hours: 4),
        ),
    actions: [
      RuleAction(
        type: output.actionType,
        messageTemplate: outputText,
        probabilityPercent: output == RuleOutputKind.probability
            ? probability
            : null,
      ),
    ],
    allowStaleData: allowStaleData,
    createdAt: testNow,
    updatedAt: testNow,
  );

  Future<void> pumpCard(
    WidgetTester tester,
    InterpretationResult result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RuleInterpretationCard(result: result, now: testNow),
          ),
        ),
      ),
    );
  }

  InterpretationResult evaluate({
    required Rule evaluated,
    required RemoteDeviceState? partnerState,
  }) => service
      .evaluate(
        rules: [evaluated],
        partnerState: partnerState,
        nowUtc: testNow,
      )
      .results
      .single;

  testWidgets('shows the rule, the user interpretation and a labelled '
      'probability', (tester) async {
    final result = evaluate(
      evaluated: rule(),
      partnerState: testPartnerState(
        chargingState: 'charging',
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      ),
    );

    await pumpCard(tester, result);

    expect(find.text('Long Charging'), findsOneWidget);
    expect(find.text('Based on your rule'), findsOneWidget);
    expect(find.text('Possible sleep period'), findsOneWidget);
    expect(find.text('User-defined probability: 70%'), findsOneWidget);
    expect(find.byType(InterpretationTypeBadge), findsOneWidget);
    expect(find.text('User-defined probability'), findsOneWidget);
  });

  testWidgets('shows the observed facts and the rule condition that used them',
      (tester) async {
    final result = evaluate(
      evaluated: rule(),
      partnerState: testPartnerState(
        chargingState: 'charging',
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      ),
    );

    await pumpCard(tester, result);

    expect(find.text('Why this rule matched'), findsOneWidget);
    expect(
      find.textContaining('Charging duration: 4h 10m'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Rule condition: Charging duration is at least 4 hours',
      ),
      findsOneWidget,
    );
  });

  testWidgets('never renders an unsupported claim about the person',
      (tester) async {
    final result = evaluate(
      evaluated: rule(),
      partnerState: testPartnerState(
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      ),
    );

    await pumpCard(tester, result);

    for (final forbidden in const [
      'sleeping',
      'asleep',
      'powered off',
      'turned off',
      'definitely',
      'WARNING',
      'ALERT',
    ]) {
      expect(
        find.textContaining(forbidden, findRichText: true),
        findsNothing,
        reason: 'the card must not state "$forbidden"',
      );
    }
  });

  testWidgets('reports how current the evidence is', (tester) async {
    final result = evaluate(
      evaluated: rule(),
      partnerState: testPartnerState(
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      ),
    );

    await pumpCard(tester, result);

    expect(find.text('Updated just now'), findsOneWidget);
    expect(
      find.textContaining('Last checked'),
      findsOneWidget,
    );
  });

  testWidgets('explains an undecided rule instead of inventing a result',
      (tester) async {
    final result = evaluate(
      evaluated: rule(
        name: 'Left home',
        output: RuleOutputKind.status,
        outputText: 'Away from home',
        condition: const RuleCondition(
          metric: RuleMetric.distanceFromHomeKm,
          operator: RuleOperator.greaterThan,
          numericThreshold: 5,
        ),
      ),
      // The partner shares nothing, so the location is unknown.
      partnerState: testPartnerState(),
    );

    await pumpCard(tester, result);

    expect(find.text('Not enough information'), findsOneWidget);
    expect(
      find.textContaining('not available yet'),
      findsOneWidget,
    );
    // The configured wording is never presented as an outcome.
    expect(find.text('Based on your rule'), findsNothing);
    expect(find.text('Away from home'), findsNothing);
    expect(find.text('Left home'), findsOneWidget);
    expect(find.text('Your rule'), findsOneWidget);
  });

  testWidgets('marks a stale interpretation as no longer current',
      (tester) async {
    final result = evaluate(
      evaluated: rule(
        allowStaleData: true,
        condition: const RuleCondition(
          metric: RuleMetric.distanceFromHomeKm,
          operator: RuleOperator.greaterThan,
          numericThreshold: 5,
        ),
      ),
      partnerState: testPartnerState(
        observedAt: testNow.subtract(const Duration(minutes: 45)),
        locationObservedAt: testNow.subtract(const Duration(minutes: 45)),
        latitude: 52.1,
        longitude: 4.3,
        distanceFromHomeKm: 7.25,
      ),
    );

    await pumpCard(tester, result);

    expect(find.text('Based on your rule'), findsOneWidget);
    expect(
      find.textContaining('no longer current'),
      findsWidgets,
    );
    expect(find.textContaining('Last updated'), findsOneWidget);
  });

  testWidgets('a status rule shows no probability at all', (tester) async {
    final result = evaluate(
      evaluated: rule(
        output: RuleOutputKind.status,
        outputText: 'Charging for a long time',
        probability: null,
      ),
      partnerState: testPartnerState(
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      ),
    );

    await pumpCard(tester, result);

    expect(find.text('Charging for a long time'), findsOneWidget);
    expect(find.textContaining('User-defined probability'), findsNothing);
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets('a long rule name and message wrap without overflowing',
      (tester) async {
    final result = evaluate(
      evaluated: rule(
        name: 'A very long rule name that should be allowed to wrap across '
            'two lines without overflowing the card',
        outputText:
            'A long user-defined interpretation sentence that also needs to '
            'wrap calmly inside the card without breaking the layout',
      ),
      partnerState: testPartnerState(
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      ),
    );

    await pumpCard(tester, result);

    expect(tester.takeException(), isNull);
  });
}
