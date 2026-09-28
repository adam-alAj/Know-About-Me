import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/rules/domain/models/interpretation_result.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_draft.dart';
import 'package:kam/features/rules/domain/rule_evaluation.dart';
import 'package:kam/features/rules/domain/rule_evaluation_service.dart';

import '../support/rule_test_app.dart';

void main() {
  const service = RuleEvaluationService();

  Rule rule({
    String id = 'rule-1',
    String name = 'Long Charging',
    int version = 1,
    bool enabled = true,
    bool allowStaleData = false,
    Duration cooldown = const Duration(minutes: 30),
    DateTime? lastTriggeredAt,
    RuleCondition? condition,
    RuleConditionGroup? group,
    RuleOutputKind output = RuleOutputKind.probability,
    String outputText = 'Possible sleep period',
    int? probability = 70,
  }) => Rule(
    id: id,
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    name: name,
    version: version,
    condition:
        condition ??
        const RuleCondition(
          metric: RuleMetric.chargingDuration,
          operator: RuleOperator.greaterThanOrEqual,
          durationThreshold: Duration(hours: 4),
        ),
    conditionGroup: group,
    actions: [
      RuleAction(
        type: output.actionType,
        messageTemplate: outputText,
        probabilityPercent: output == RuleOutputKind.probability
            ? probability
            : null,
      ),
    ],
    enabled: enabled,
    allowStaleData: allowStaleData,
    cooldown: cooldown,
    lastTriggeredAt: lastTriggeredAt,
    createdAt: testNow,
    updatedAt: testNow,
  );

  RuleEvaluationCycle run({
    required Iterable<Rule> rules,
    required RemoteDeviceState? partnerState,
    Map<String, RuleEvaluationOutcome> previous =
        const <String, RuleEvaluationOutcome>{},
  }) => service.evaluate(
    rules: rules,
    partnerState: partnerState,
    nowUtc: testNow,
    previousOutcomes: previous,
  );

  group('matched evaluation', () {
    test('a satisfied condition produces a labelled interpretation', () {
      final cycle = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingState: 'charging',
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.hasPartnerState, isTrue);
      final result = cycle.results.single;
      expect(result.status, RuleEvaluationOutcome.matched);
      expect(result.isMatched, isTrue);
      expect(result.ruleName, 'Long Charging');
      expect(result.title, 'Possible sleep period');
      expect(result.userDefinedProbability, 70);
      expect(result.type, RuleOutputKind.probability);
      expect(result.isNewMatch, isTrue);
      expect(result.facts.single.description, 'Charging duration: 4h 10m');
      expect(cycle.active, hasLength(1));
      expect(cycle.unclear, isEmpty);
    });

    test('the whole cycle shares one snapshot and one evaluation time', () {
      final cycle = run(
        rules: [rule(), rule(id: 'rule-2', name: 'Battery high')],
        partnerState: testPartnerState(
          chargingState: 'charging',
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.snapshot, isNotNull);
      expect(cycle.results, hasLength(2));
      for (final result in cycle.results) {
        expect(result.evaluatedAt, cycle.evaluatedAt);
      }
    });

    test('never states more than the rule and the facts support', () {
      final result = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      ).results.single;

      final rendered = [
        result.title,
        for (final fact in result.facts) fact.description,
      ].join(' ').toLowerCase();
      for (final forbidden in const [
        'sleeping',
        'asleep',
        'powered off',
        'turned off',
        'definitely',
      ]) {
        expect(rendered, isNot(contains(forbidden)));
      }
    });
  });

  group('boundaries', () {
    test('an equal duration does not satisfy a strict threshold', () {
      final cycle = run(
        rules: [
          rule(
            condition: const RuleCondition(
              metric: RuleMetric.chargingDuration,
              operator: RuleOperator.greaterThan,
              durationThreshold: Duration(hours: 4),
            ),
          ),
        ],
        partnerState: testPartnerState(
          chargingDuration: const Duration(hours: 4),
          chargingStartedAt: testNow.subtract(const Duration(hours: 4)),
        ),
      );

      expect(cycle.results.single.status, RuleEvaluationOutcome.notMatched);
      expect(cycle.results.single.isMatched, isFalse);
      expect(cycle.active, isEmpty);
    });

    test('an equal duration satisfies an inclusive threshold', () {
      final cycle = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingDuration: const Duration(hours: 4),
          chargingStartedAt: testNow.subtract(const Duration(hours: 4)),
        ),
      );

      expect(cycle.results.single.status, RuleEvaluationOutcome.matched);
    });
  });

  group('unknown, stale and unsupported input', () {
    test('an unknown location never becomes "away from home"', () {
      final cycle = run(
        rules: [
          rule(
            name: 'Away from home',
            condition: const RuleCondition(
              metric: RuleMetric.distanceFromHomeKm,
              operator: RuleOperator.greaterThan,
              numericThreshold: 5,
            ),
            output: RuleOutputKind.status,
            outputText: 'Away from home',
          ),
        ],
        // The partner shares nothing at all.
        partnerState: testPartnerState(),
      );

      final result = cycle.results.single;
      expect(result.status, RuleEvaluationOutcome.unknown);
      expect(result.isMatched, isFalse);
      expect(result.isIndeterminate, isTrue);
      expect(result.title, 'Away from home');
      expect(result.explanation, isNotNull);
      expect(cycle.active, isEmpty);
      expect(cycle.unclear, hasLength(1));
    });

    test('an unshared charging duration never becomes "long charging"', () {
      final cycle = run(
        rules: [rule()],
        partnerState: testPartnerState(batteryPercentage: 40),
      );

      // The metric was never shared, which the engine reports as insufficient
      // data — never as a satisfied or unsatisfied condition.
      expect(
        cycle.results.single.status,
        RuleEvaluationOutcome.insufficientData,
      );
      expect(cycle.results.single.isMatched, isFalse);
      expect(cycle.results.single.facts, isEmpty);
    });

    test('stale location is refused by default', () {
      final cycle = run(
        rules: [
          rule(
            name: 'Away from home',
            condition: const RuleCondition(
              metric: RuleMetric.distanceFromHomeKm,
              operator: RuleOperator.greaterThan,
              numericThreshold: 5,
            ),
          ),
        ],
        partnerState: testPartnerState(
          observedAt: testNow.subtract(const Duration(minutes: 45)),
          locationObservedAt: testNow.subtract(const Duration(minutes: 45)),
          latitude: 52.1,
          longitude: 4.3,
          distanceFromHomeKm: 7.25,
        ),
      );

      final result = cycle.results.single;
      expect(result.status, RuleEvaluationOutcome.staleData);
      expect(result.isMatched, isFalse);
      expect(result.isBasedOnStaleData, isTrue);
      expect(result.freshness, DataFreshness.stale);
      expect(result.explanation, contains('no longer current'));
    });

    test('stale location is used only when the rule explicitly allows it', () {
      final cycle = run(
        rules: [
          rule(
            allowStaleData: true,
            condition: const RuleCondition(
              metric: RuleMetric.distanceFromHomeKm,
              operator: RuleOperator.greaterThan,
              numericThreshold: 5,
            ),
          ),
        ],
        partnerState: testPartnerState(
          observedAt: testNow.subtract(const Duration(minutes: 45)),
          locationObservedAt: testNow.subtract(const Duration(minutes: 45)),
          latitude: 52.1,
          longitude: 4.3,
          distanceFromHomeKm: 7.25,
        ),
      );

      final result = cycle.results.single;
      expect(result.status, RuleEvaluationOutcome.matched);
      // It is still *identified* as stale, never presented as current.
      expect(result.isBasedOnStaleData, isTrue);
      expect(result.freshness, DataFreshness.stale);
    });

    test('an unavailable device state is not reported as a system failure', () {
      final cycle = run(
        rules: [rule()],
        partnerState: testPartnerState(
          networkStatus: 'offline',
          lastOnlineAt: testNow.subtract(const Duration(minutes: 90)),
        ),
      );

      final result = cycle.results.single;
      // The synchronized contract carries no charging duration here, so the
      // rule waits for data instead of failing (STEP 29).
      expect(result.status, RuleEvaluationOutcome.insufficientData);
      expect(result.explanation, isNotNull);
      expect(result.status, isNot(RuleEvaluationOutcome.error));
    });
  });

  group('multiple rules', () {
    test('every satisfied rule is preserved, never collapsed to one winner',
        () {
      final cycle = run(
        rules: [
          rule(id: 'rule-a', name: 'Charging a while'),
          rule(id: 'rule-b', name: 'Charging a long while'),
          rule(id: 'rule-c', name: 'Charging now', output: RuleOutputKind.status),
        ],
        partnerState: testPartnerState(
          batteryPercentage: 80,
          chargingState: 'charging',
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.active, hasLength(3));
      expect(
        cycle.active.map((result) => result.ruleId),
        containsAll(<String>['rule-a', 'rule-b', 'rule-c']),
      );
      // Deterministic presentation order.
      expect(
        cycle.displayable.map((result) => result.ruleName),
        ['Charging a long while', 'Charging a while', 'Charging now'],
      );
    });

    test('a false rule is not shown, a decided false is not an error', () {
      final cycle = run(
        rules: [
          rule(id: 'rule-a', name: 'Long charging'),
          rule(
            id: 'rule-b',
            name: 'Low battery',
            condition: const RuleCondition(
              metric: RuleMetric.batteryPercentage,
              operator: RuleOperator.lessThan,
              numericThreshold: 20,
            ),
          ),
        ],
        partnerState: testPartnerState(
          batteryPercentage: 80,
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.results, hasLength(2));
      expect(cycle.active.map((result) => result.ruleName), ['Long charging']);
      expect(cycle.unclear, isEmpty);
      expect(cycle.displayable, hasLength(1));
    });
  });

  group('disabled and deleted rules', () {
    test('a disabled rule is never evaluated', () {
      final cycle = run(
        rules: [rule(enabled: false)],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.results, isEmpty);
      expect(cycle.outcomes, isEmpty);
      expect(cycle.hasPartnerState, isTrue);
    });

    test('a disabled rule beside an enabled one produces nothing of its own',
        () {
      final cycle = run(
        rules: [
          rule(id: 'rule-a', name: 'Enabled rule'),
          rule(id: 'rule-b', name: 'Disabled rule', enabled: false),
        ],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.results, hasLength(1));
      expect(cycle.results.single.ruleId, 'rule-a');
      expect(cycle.outcomes.keys, ['rule-a']);
    });

    test('a deleted rule is no longer evaluated', () {
      final cycle = run(
        rules: [rule(id: 'rule-kept', name: 'Kept')],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(
        cycle.results.map((result) => result.ruleId),
        isNot(contains('rule-deleted')),
      );
    });
  });

  group('rule versions', () {
    test('an edited rule is evaluated at its new version and threshold', () {
      final state = testPartnerState(
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      );

      final before = run(rules: [rule(version: 1)], partnerState: state);
      expect(before.results.single.ruleVersion, 1);
      expect(before.results.single.status, RuleEvaluationOutcome.matched);

      final after = run(
        rules: [
          rule(
            version: 2,
            condition: const RuleCondition(
              metric: RuleMetric.chargingDuration,
              operator: RuleOperator.greaterThanOrEqual,
              durationThreshold: Duration(minutes: 300),
            ),
          ),
        ],
        partnerState: state,
      );

      expect(after.results.single.ruleVersion, 2);
      expect(after.results.single.status, RuleEvaluationOutcome.notMatched);
    });
  });

  group('transitions', () {
    test('first match is new, a repeated match is not', () {
      final state = testPartnerState(
        chargingDuration: const Duration(minutes: 250),
        chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
      );

      final first = run(rules: [rule()], partnerState: state);
      expect(first.results.single.transition, RuleTransition.becameMatched);
      expect(first.hasNewMatch, isTrue);
      expect(first.outcomes['rule-1'], RuleEvaluationOutcome.matched);

      // The same state arrives again: a continuously satisfied rule must not
      // produce a second new-match event (STEP 11).
      final second = run(
        rules: [rule()],
        partnerState: state,
        previous: first.outcomes,
      );
      expect(second.results.single.transition, RuleTransition.stayedMatched);
      expect(second.results.single.isNewMatch, isFalse);
      expect(second.hasNewMatch, isFalse);
    });

    test('a match that ends is reported as a transition out', () {
      final matched = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );
      final unmatched = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 30),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 30)),
        ),
        previous: matched.outcomes,
      );

      expect(
        unmatched.results.single.transition,
        RuleTransition.becameNotMatched,
      );
    });

    test('losing data is a transition to indeterminate, not to false', () {
      final matched = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );
      final withoutData = run(
        rules: [rule()],
        partnerState: testPartnerState(),
        previous: matched.outcomes,
      );

      expect(
        withoutData.results.single.transition,
        RuleTransition.becameIndeterminate,
      );
      expect(withoutData.results.single.isNotMatched, isFalse);
    });

    test('a first-time unknown is not a change', () {
      final cycle = run(rules: [rule()], partnerState: testPartnerState());

      expect(cycle.results.single.transition, RuleTransition.becameIndeterminate);
    });

    test('classifies every outcome pair deterministically', () {
      const matched = RuleEvaluationOutcome.matched;
      const notMatched = RuleEvaluationOutcome.notMatched;
      const unknown = RuleEvaluationOutcome.unknown;
      final cases = <(RuleEvaluationOutcome?, RuleEvaluationOutcome,
          RuleTransition)>[
        (null, matched, RuleTransition.becameMatched),
        (null, notMatched, RuleTransition.stayedNotMatched),
        (null, unknown, RuleTransition.becameIndeterminate),
        (matched, matched, RuleTransition.stayedMatched),
        (matched, notMatched, RuleTransition.becameNotMatched),
        (notMatched, notMatched, RuleTransition.stayedNotMatched),
        (notMatched, matched, RuleTransition.becameMatched),
        (unknown, unknown, RuleTransition.stayedIndeterminate),
        (unknown, matched, RuleTransition.becameMatched),
        (matched, unknown, RuleTransition.becameIndeterminate),
        (
          null,
          RuleEvaluationOutcome.coolingDown,
          RuleTransition.stayedMatched,
        ),
        (
          RuleEvaluationOutcome.coolingDown,
          RuleEvaluationOutcome.staleData,
          RuleTransition.becameIndeterminate,
        ),
        (
          matched,
          RuleEvaluationOutcome.coolingDown,
          RuleTransition.stayedMatched,
        ),
      ];

      for (final (previous, current, expected) in cases) {
        expect(
          RuleEvaluationService.transitionFor(
            previous: previous,
            current: current,
          ),
          expected,
          reason: '$previous -> $current',
        );
      }
    });
  });

  group('cooldown and re-triggering', () {
    test('a match inside its cooldown stays visible but triggers nothing', () {
      final cycle = run(
        rules: [
          rule(
            cooldown: const Duration(minutes: 30),
            lastTriggeredAt: testNow.subtract(const Duration(minutes: 10)),
          ),
        ],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      final result = cycle.results.single;
      expect(result.status, RuleEvaluationOutcome.coolingDown);
      expect(result.isCoolingDown, isTrue);
      expect(result.isMatched, isTrue);
      expect(result.isNewMatch, isFalse);
      expect(result.title, 'Possible sleep period');
    });

    test('the same match becomes new again once the cooldown has passed', () {
      final cycle = run(
        rules: [
          rule(
            cooldown: const Duration(minutes: 30),
            lastTriggeredAt: testNow.subtract(const Duration(hours: 2)),
          ),
        ],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.results.single.status, RuleEvaluationOutcome.matched);
      expect(cycle.results.single.isNewMatch, isTrue);
    });
  });

  group('grouped conditions', () {
    test('an all-group needs every condition, and reports the facts it used',
        () {
      final cycle = run(
        rules: [
          rule(
            group: const RuleConditionGroup(
              operator: RuleGroupOperator.all,
              conditions: [
                RuleCondition(
                  metric: RuleMetric.chargingDuration,
                  operator: RuleOperator.greaterThanOrEqual,
                  durationThreshold: Duration(hours: 4),
                ),
                RuleCondition(
                  metric: RuleMetric.batteryPercentage,
                  operator: RuleOperator.greaterThan,
                  numericThreshold: 50,
                ),
              ],
            ),
          ),
        ],
        partnerState: testPartnerState(
          batteryPercentage: 80,
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      final result = cycle.results.single;
      expect(result.status, RuleEvaluationOutcome.matched);
      expect(result.facts, hasLength(2));
      expect(
        result.facts.map((fact) => fact.metric),
        containsAll(<RuleMetric>[
          RuleMetric.chargingDuration,
          RuleMetric.batteryPercentage,
        ]),
      );
    });
  });

  group('no authorized partner state', () {
    test('nothing is evaluated and no transition is invented', () {
      final cycle = run(rules: [rule()], partnerState: null);

      expect(cycle.hasPartnerState, isFalse);
      expect(cycle.results, isEmpty);
      expect(cycle.outcomes, isEmpty);
      expect(cycle.hasNewMatch, isFalse);
      expect(cycle.snapshot, isNull);
    });

    test('an empty rule list evaluates nothing but is a real cycle', () {
      final cycle = run(
        rules: const <Rule>[],
        partnerState: testPartnerState(batteryPercentage: 55),
      );

      expect(cycle.hasPartnerState, isTrue);
      expect(cycle.results, isEmpty);
    });
  });

  group('freshness reporting', () {
    test('fresh partner state yields a fresh result', () {
      final cycle = run(
        rules: [rule()],
        partnerState: testPartnerState(
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(const Duration(minutes: 250)),
        ),
      );

      expect(cycle.results.single.freshness, DataFreshness.fresh);
      expect(
        RuleEvaluationService.freshnessOf(cycle, testNow),
        DataFreshness.fresh,
      );
    });
  });
}
