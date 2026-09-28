import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/rules/domain/models/interpretation.dart';
import 'package:kam/features/rules/domain/models/rule.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26, 12);

  Rule buildRule({DateTime? lastTriggeredAt}) {
    return Rule(
      id: 'rule-1',
      ownerUserId: 'user-a',
      pairId: 'pair-1',
      name: 'Possible sleep',
      condition: const RuleCondition(
        metric: RuleMetric.chargingDuration,
        operator: RuleOperator.greaterThan,
        numericThreshold: 240,
      ),
      actions: const [
        RuleAction(
          type: RuleActionType.displayProbability,
          messageTemplate:
              'There is a {probability}% possibility that {partnerName} is sleeping now.',
          probabilityPercent: 70,
        ),
      ],
      cooldown: const Duration(minutes: 30),
      lastTriggeredAt: lastTriggeredAt,
    );
  }

  group('Rule', () {
    test('carries its condition, actions and enabled state', () {
      final rule = buildRule();

      expect(rule.enabled, isTrue);
      expect(rule.condition.metric, RuleMetric.chargingDuration);
      expect(rule.condition.operator, RuleOperator.greaterThan);
      expect(rule.condition.numericThreshold, 240);
      expect(rule.actions.single.probabilityPercent, 70);
    });

    test('suppresses repeated notifications during cooldown', () {
      final rule = buildRule(
        lastTriggeredAt: now.subtract(const Duration(minutes: 5)),
      );

      expect(rule.isCoolingDownAt(now), isTrue);
    });

    test('allows a new notification after the cooldown elapses', () {
      final rule = buildRule(
        lastTriggeredAt: now.subtract(const Duration(minutes: 45)),
      );

      expect(rule.isCoolingDownAt(now), isFalse);
    });

    test('cooldown ends at the exact configured duration boundary', () {
      final rule = buildRule(
        lastTriggeredAt: now.subtract(const Duration(minutes: 30)),
      );

      expect(rule.isCoolingDownAt(now), isFalse);
    });

    test('a probability action requires a user-configured percentage', () {
      expect(
        () => RuleAction(type: RuleActionType.displayProbability),
        throwsA(isA<AssertionError>()),
      );
    });

    test('user-defined probability accepts only 0 through 100 inclusive', () {
      for (final value in [0, 50, 100]) {
        expect(
          RuleAction(
            type: RuleActionType.displayProbability,
            probabilityPercent: value,
          ).probabilityPercent,
          value,
        );
      }
      for (final value in [-1, 101]) {
        expect(
          () => RuleAction(
            type: RuleActionType.displayProbability,
            probabilityPercent: value,
          ),
          throwsA(isA<AssertionError>()),
        );
      }
    });

    test(
      'rule validation catches state strings outside the closed vocabulary',
      () {
        final invalid = Rule(
          id: 'rule-1',
          ownerUserId: 'user-a',
          pairId: 'pair-1',
          name: 'Invalid state',
          condition: const RuleCondition(
            metric: RuleMetric.networkType,
            operator: RuleOperator.isA,
            stateValue: 'space-network',
          ),
          actions: const [],
        );
        expect(
          invalid.validate().map((issue) => issue.code),
          contains('invalid_state_value'),
        );
      },
    );
  });

  group('Interpretation', () {
    test('is never presented as an objective fact', () {
      final interpretation = Interpretation(
        id: 'interp-1',
        ruleId: 'rule-1',
        ownerUserId: 'user-a',
        pairId: 'pair-1',
        message: 'There is a 70% possibility that Afraa is sleeping now.',
        probabilityPercent: 70,
        basis: const [
          InterpretationBasis(
            metric: RuleMetric.chargingDuration,
            description: 'Phone has been charging for 4h 08m',
            formattedValue: '4h 08m',
          ),
        ],
        producedAt: now,
      );

      expect(interpretation.isObjectiveFact, isFalse);
      expect(interpretation.hasUserDefinedProbability, isTrue);
      expect(interpretation.probabilityPercent, 70);
      expect(interpretation.basis.single.metric, RuleMetric.chargingDuration);
    });
  });
}
