import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/features/rules/domain/interpretation_builder.dart';
import 'package:kam/features/rules/domain/models/interpretation.dart';
import 'package:kam/features/rules/domain/models/interpretation_result.dart';
import 'package:kam/features/rules/domain/metric_definition.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_draft.dart';
import 'package:kam/features/rules/domain/rule_evaluation.dart';

import '../support/rule_test_app.dart';

void main() {
  const builder = InterpretationBuilder();

  Rule rule({
    RuleActionType type = RuleActionType.displayProbability,
    String message = 'Possible sleep period',
    int? probability = 70,
    int version = 1,
  }) => Rule(
    id: 'rule-1',
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    name: 'Long Charging',
    version: version,
    condition: const RuleCondition(
      metric: RuleMetric.chargingDuration,
      operator: RuleOperator.greaterThanOrEqual,
      durationThreshold: Duration(hours: 4),
    ),
    actions: [
      RuleAction(
        type: type,
        messageTemplate: message,
        probabilityPercent: probability,
      ),
    ],
    createdAt: testNow,
    updatedAt: testNow,
  );

  RuleEvaluationResult evaluation({
    RuleEvaluationOutcome outcome = RuleEvaluationOutcome.matched,
    Interpretation? interpretation,
    List<String> staleInputMetrics = const <String>[],
    int version = 1,
    String? note,
  }) => RuleEvaluationResult(
    ruleId: 'rule-1',
    ruleVersion: version,
    outcome: outcome,
    evaluatedAt: testNow,
    staleInputMetrics: staleInputMetrics,
    interpretation: interpretation,
    note: note,
  );

  Interpretation sleeping() => Interpretation(
    id: 'rule-1:v1:chargingDuration:2026-09-28T07:49:00.000Z',
    ruleId: 'rule-1',
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    message:
        'There is a user-defined 70% possibility that Possible sleep period',
    probabilityPercent: 70,
    basis: [
      InterpretationBasis(
        metric: RuleMetric.chargingDuration,
        description: 'Charging duration: 4h 11m',
        observedAt: testNow.subtract(const Duration(hours: 4, minutes: 11)),
      ),
    ],
    producedAt: testNow,
  );

  group('matched results', () {
    test('carries the user interpretation and labels its probability', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(interpretation: sleeping()),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        freshness: DataFreshness.fresh,
        evidenceTime: testNow,
      );

      expect(result.type, RuleOutputKind.probability);
      expect(result.title, 'Possible sleep period');
      expect(result.userDefinedProbability, 70);
      expect(result.hasUserDefinedProbability, isTrue);
      expect(result.isMatched, isTrue);
      expect(result.isNewMatch, isTrue);
      expect(result.explanation, isNull);
      // The generated engine sentence is preserved for the notification layer
      // rather than shown as a measured claim.
      expect(result.engineMessage, contains('possibility'));
    });

    test('exposes only the observed facts the engine recorded', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(interpretation: sleeping()),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        evidenceTime: testNow,
      );

      expect(result.facts, hasLength(1));
      expect(result.facts.single.metric, RuleMetric.chargingDuration);
      expect(result.facts.single.description, 'Charging duration: 4h 11m');
      expect(result.facts.single.observedAt, isNotNull);
    });

    test('never turns the user wording into a fact-bearing statement', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(interpretation: sleeping()),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        evidenceTime: testNow,
      );

      final rendered = [
        result.title,
        for (final fact in result.facts) fact.description,
      ].join(' ');
      for (final forbidden in const [
        'is sleeping',
        'are asleep',
        'definitely',
        'probably sleeping',
        'phone is powered off',
        'phone is turned off',
      ]) {
        expect(rendered.toLowerCase(), isNot(contains(forbidden)));
      }
    });

    test('reports the evidence time, not the oldest fact anchor', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(interpretation: sleeping()),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        freshness: DataFreshness.fresh,
        evidenceTime: testNow,
      );

      // The charging anchor is over four hours old, but the *state* behind the
      // interpretation is current, and that is what freshness must describe.
      expect(result.observationTime, testNow);
      expect(result.freshness, DataFreshness.fresh);
      expect(result.isBasedOnStaleData, isFalse);
    });

    test('keeps a status rule free of any probability', () {
      final result = builder.build(
        rule: rule(
          type: RuleActionType.displayStatus,
          message: 'Away from home',
          probability: null,
        ),
        evaluation: evaluation(
          interpretation: Interpretation(
            id: 'id',
            ruleId: 'rule-1',
            ownerUserId: 'user-a',
            pairId: 'pair-1',
            message: 'There is a possibility that Away from home',
            basis: const [],
            producedAt: testNow,
          ),
        ),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        evidenceTime: testNow,
      );

      expect(result.type, RuleOutputKind.status);
      expect(result.title, 'Away from home');
      expect(result.userDefinedProbability, isNull);
      expect(result.hasUserDefinedProbability, isFalse);
    });

    test('preserves the rule version it was evaluated at', () {
      final result = builder.build(
        rule: rule(version: 4),
        evaluation: evaluation(version: 4, interpretation: sleeping()),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        evidenceTime: testNow,
      );

      expect(result.ruleVersion, 4);
      expect(result.ruleId, 'rule-1');
    });
  });

  group('indeterminate results', () {
    const explanationFor = <RuleEvaluationOutcome, String>{
      RuleEvaluationOutcome.unknown:
          'Some of the information this rule needs is not available yet.',
      RuleEvaluationOutcome.staleData:
          'This rule is based on information that is no longer current.',
      RuleEvaluationOutcome.unsupported:
          'This device cannot report some of the information this rule needs.',
      RuleEvaluationOutcome.permissionDenied:
          'Sharing for some of the information this rule needs is turned off.',
      RuleEvaluationOutcome.insufficientData:
          'Some of the information this rule needs has not been shared.',
      RuleEvaluationOutcome.error: 'This rule could not be checked.',
    };

    for (final entry in explanationFor.entries) {
      test('explains ${entry.key.name} without an error code', () {
        final result = builder.build(
          rule: rule(),
          evaluation: evaluation(outcome: entry.key, note: 'metric_123 stale'),
          transition: RuleTransition.becameIndeterminate,
          nowUtc: testNow,
          evidenceTime: testNow,
        );

        expect(result.isIndeterminate, isTrue);
        expect(result.isMatched, isFalse);
        expect(result.explanation, entry.value);
        // The engine's internal note never reaches the user.
        expect(result.explanation, isNot(contains('metric_123')));
      });
    }

    test('forces stale freshness when the engine flagged a stale input', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(
          outcome: RuleEvaluationOutcome.matched,
          interpretation: sleeping(),
          staleInputMetrics: const ['chargingDuration'],
        ),
        transition: RuleTransition.becameMatched,
        nowUtc: testNow,
        // Even a caller that believes the data is fresh cannot override the
        // engine's own staleness finding.
        freshness: DataFreshness.fresh,
        evidenceTime: testNow,
      );

      expect(result.freshness, DataFreshness.stale);
      expect(result.isBasedOnStaleData, isTrue);
    });

    test('reports unknown freshness when there is no evidence time', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(outcome: RuleEvaluationOutcome.unknown),
        transition: RuleTransition.becameIndeterminate,
        nowUtc: testNow,
      );

      expect(result.freshness, DataFreshness.unknown);
      expect(result.observationTime, isNull);
    });

    test('classifies the supplied evidence time through the policy', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(
          outcome: RuleEvaluationOutcome.unknown,
          interpretation: sleeping(),
        ),
        transition: RuleTransition.becameIndeterminate,
        nowUtc: testNow,
        evidenceTime: testNow.subtract(const Duration(minutes: 10)),
      );

      expect(result.freshness, DataFreshness.recent);
    });
  });

  group('user-defined probability boundaries', () {
    test('accepts 0 and 100 as user-defined values', () {
      for (final percent in const [0, 100]) {
        final result = builder.build(
          rule: rule(probability: percent),
          evaluation: evaluation(interpretation: sleeping()),
          transition: RuleTransition.becameMatched,
          nowUtc: testNow,
          evidenceTime: testNow,
        );
        expect(result.userDefinedProbability, percent);
        expect(result.hasUserDefinedProbability, isTrue);
      }
    });

    test('out-of-range percentages cannot be authored in the first place', () {
      for (final invalid in const ['-1', '101', ''] ) {
        final draft = RuleDraft.newRule(
          ownerUserId: 'user-a',
          pairId: 'pair-1',
        ).copyWith(
          name: 'Long Charging',
          outputKind: RuleOutputKind.probability,
          outputText: 'Possible sleep period',
          probabilityText: invalid,
          conditions: [
            ruleDraftCondition(const Duration(hours: 4)),
          ],
        );
        expect(draft.isValid, isFalse, reason: 'probability "$invalid"');
        expect(
          draft.validate().map((issue) => issue.code),
          contains('invalid_probability'),
        );
      }
    });
  });

  group('transition handling', () {
    test('a repeated match is not a new match', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(interpretation: sleeping()),
        transition: RuleTransition.stayedMatched,
        nowUtc: testNow,
        evidenceTime: testNow,
      );

      expect(result.isMatched, isTrue);
      expect(result.isNewMatch, isFalse);
    });

    test('a cooling-down match stays visible but is not new', () {
      final result = builder.build(
        rule: rule(),
        evaluation: evaluation(
          outcome: RuleEvaluationOutcome.coolingDown,
          interpretation: sleeping(),
        ),
        transition: RuleTransition.stayedMatched,
        nowUtc: testNow,
        evidenceTime: testNow,
      );

      expect(result.isMatched, isTrue);
      expect(result.isCoolingDown, isTrue);
      expect(result.isNewMatch, isFalse);
    });
  });

  group('rule output helpers', () {
    test('read the interpretation straight off the persisted rule', () {
      expect(ruleOutputKindOf(rule()), RuleOutputKind.probability);
      expect(ruleInterpretationTextOf(rule()), 'Possible sleep period');
      expect(ruleUserDefinedProbabilityOf(rule()), 70);
      expect(
        ruleOutputKindOf(
          rule(
            type: RuleActionType.displayMessage,
            message: 'No recent activity was observed',
            probability: null,
          ),
        ),
        RuleOutputKind.message,
      );
    });

    test('fall back to a status when the rule has no renderable output', () {
      final notificationOnly = Rule(
        id: 'rule-2',
        ownerUserId: 'user-a',
        pairId: 'pair-1',
        name: 'Notify only',
        condition: const RuleCondition(
          metric: RuleMetric.batteryPercentage,
          operator: RuleOperator.lessThan,
          numericThreshold: 20,
        ),
        actions: const [
          RuleAction(type: RuleActionType.triggerNotification),
        ],
        createdAt: testNow,
        updatedAt: testNow,
      );

      expect(ruleOutputKindOf(notificationOnly), RuleOutputKind.status);
      expect(ruleInterpretationTextOf(notificationOnly), isNull);
      expect(ruleUserDefinedProbabilityOf(notificationOnly), isNull);
    });
  });
}

RuleDraftCondition ruleDraftCondition(Duration threshold) => RuleDraftCondition(
  metric: RuleMetric.chargingDuration,
  operator: RuleOperator.greaterThanOrEqual,
  numericText: threshold.inHours.toString(),
  durationUnit: DurationUnit.hours,
);
