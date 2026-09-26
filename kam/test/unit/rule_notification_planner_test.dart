import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/auth/domain/models/user_preferences.dart';
import 'package:kam/features/notifications/domain/rule_notification_planner.dart';
import 'package:kam/features/rules/domain/models/interpretation.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_evaluation.dart';

/// Tests for the notification planner — the Spark-only replacement for a
/// notification-dispatch Cloud Function.
///
/// The planner is pure: it takes an already-computed evaluation and decides
/// whether the user's own device should raise a local notification.
void main() {
  final at = DateTime.utc(2026, 9, 26, 12);

  const condition = RuleCondition(
    metric: RuleMetric.chargingDuration,
    operator: RuleOperator.greaterThanOrEqual,
    numericThreshold: 240,
  );

  const rule = Rule(
    id: 'r1',
    ownerUserId: 'uA',
    pairId: 'p1',
    name: 'Possible sleep',
    condition: condition,
    actions: [
      RuleAction(
        type: RuleActionType.displayProbability,
        messageTemplate: 'Afraa is sleeping now',
        probabilityPercent: 70,
      ),
    ],
  );

  Interpretation interpretation() => Interpretation(
    id: 'r1@2026-09-26T12:00:00.000Z',
    ruleId: 'r1',
    ownerUserId: 'uA',
    pairId: 'p1',
    message: 'There is a 70% possibility that Afraa is sleeping now.',
    basis: const [
      InterpretationBasis(
        metric: RuleMetric.chargingDuration,
        description: 'Charging duration: 4h 20m',
      ),
    ],
    producedAt: at,
    probabilityPercent: 70,
    sourceCondition: condition,
  );

  RuleEvaluationResult result(RuleEvaluationOutcome outcome) =>
      RuleEvaluationResult(
        ruleId: 'r1',
        outcome: outcome,
        evaluatedAt: at,
        interpretation:
            outcome == RuleEvaluationOutcome.matched ||
                outcome == RuleEvaluationOutcome.coolingDown
            ? interpretation()
            : null,
        note: outcome == RuleEvaluationOutcome.staleData
            ? 'chargingDuration is stale'
            : null,
      );

  const planner = RuleNotificationPlanner();

  group('notify', () {
    test('a match on fresh data produces a local notification plan', () {
      final plan = planner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.matched),
        preference: NotificationPreference.allRuleNotifications,
      );

      expect(plan.decision, NotificationDecision.notify);
      expect(plan.shouldNotify, isTrue);
      expect(plan.title, 'Possible sleep');
      expect(plan.body, contains('70% possibility'));
      expect(plan.dedupeKey, isNotNull);
    });
  });

  group('suppression', () {
    test('a non-match never notifies', () {
      final plan = planner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.notMatched),
        preference: NotificationPreference.allRuleNotifications,
      );

      expect(plan.decision, NotificationDecision.notMatched);
      expect(plan.shouldNotify, isFalse);
    });

    test('indeterminate results never notify and carry the reason', () {
      for (final outcome in [
        RuleEvaluationOutcome.insufficientData,
        RuleEvaluationOutcome.staleData,
      ]) {
        final plan = planner.plan(
          rule: rule,
          result: result(outcome),
          preference: NotificationPreference.allRuleNotifications,
        );

        expect(plan.decision, NotificationDecision.indeterminate);
        expect(plan.shouldNotify, isFalse);
        expect(plan.reason, isNotEmpty);
      }
    });

    test('a cooling-down match does not notify again', () {
      final plan = planner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.coolingDown),
        preference: NotificationPreference.allRuleNotifications,
      );

      expect(plan.decision, NotificationDecision.suppressedByCooldown);
      expect(plan.shouldNotify, isFalse);
    });

    test('a disabled rule never notifies', () {
      final plan = planner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.disabled),
        preference: NotificationPreference.allRuleNotifications,
      );

      expect(plan.shouldNotify, isFalse);
    });
  });

  group('user preference is authoritative (FR-042)', () {
    test('notifications turned off suppress an otherwise notifying match', () {
      final plan = planner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.matched),
        preference: NotificationPreference.noNotifications,
      );

      expect(plan.decision, NotificationDecision.suppressedByPreference);
      expect(plan.shouldNotify, isFalse);
    });

    test('specific-rules-only notifies only for marked rules', () {
      const selectingPlanner = RuleNotificationPlanner(
        notifiableRuleIds: {'someoneElse'},
      );

      final plan = selectingPlanner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.matched),
        preference: NotificationPreference.specificRulesOnly,
      );

      expect(plan.decision, NotificationDecision.suppressedByPreference);
    });

    test('important-only notifies for a rule in the marked set', () {
      const selectingPlanner = RuleNotificationPlanner(
        notifiableRuleIds: {'r1'},
      );

      final plan = selectingPlanner.plan(
        rule: rule,
        result: result(RuleEvaluationOutcome.matched),
        preference: NotificationPreference.importantOnly,
      );

      expect(plan.decision, NotificationDecision.notify);
    });
  });

  group('duplicates', () {
    test('the same interpretation is not notified twice', () {
      final evaluation = result(RuleEvaluationOutcome.matched);
      final key = evaluation.interpretation!.id;

      final plan = planner.plan(
        rule: rule,
        result: evaluation,
        preference: NotificationPreference.allRuleNotifications,
        alreadyNotifiedKeys: {key},
      );

      expect(plan.decision, NotificationDecision.duplicate);
      expect(plan.shouldNotify, isFalse);
    });
  });
}
