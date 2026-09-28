import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_evaluation_service.dart';
import 'package:kam/features/rules/domain/rule_reevaluation_scheduler.dart';

import '../support/rule_test_app.dart';

void main() {
  const service = RuleEvaluationService();

  Rule rule({
    String id = 'rule-1',
    String name = 'Long Charging',
    RuleOperator operator = RuleOperator.greaterThanOrEqual,
    Duration threshold = const Duration(hours: 4),
    RuleMetric metric = RuleMetric.chargingDuration,
  }) => Rule(
    id: id,
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    name: name,
    condition: RuleCondition(
      metric: metric,
      operator: operator,
      durationThreshold: threshold,
    ),
    actions: const [
      RuleAction(
        type: RuleActionType.displayStatus,
        messageTemplate: 'Long charging',
      ),
    ],
    createdAt: testNow,
    updatedAt: testNow,
  );

  Duration? delayFor({
    required Iterable<Rule> rules,
    required RemoteDeviceState? partnerState,
  }) {
    final cycle = service.evaluate(
      rules: rules,
      partnerState: partnerState,
      nowUtc: testNow,
    );
    return RuleReevaluationScheduler.nextDelay(
      cycle: cycle,
      nowUtc: testNow,
    );
  }

  RemoteDeviceState charging(Duration elapsed) => testPartnerState(
    chargingDuration: elapsed,
    chargingStartedAt: testNow.subtract(elapsed),
  );

  test('no partner state means nothing to plan', () {
    expect(delayFor(rules: [rule()], partnerState: null), isNull);
  });

  test('a rule with no time-dependent metric needs no re-check', () {
    expect(
      delayFor(
        rules: [
          rule(
            metric: RuleMetric.batteryPercentage,
            operator: RuleOperator.lessThan,
            threshold: const Duration(minutes: 20),
          ),
        ],
        partnerState: testPartnerState(batteryPercentage: 80),
      ),
      isNull,
    );
  });

  test('a not-yet-satisfied threshold is scheduled for exactly its crossing',
      () {
    expect(
      delayFor(
        rules: [rule(threshold: const Duration(minutes: 20))],
        partnerState: charging(const Duration(minutes: 10)),
      ),
      const Duration(minutes: 10),
    );
  });

  test('an already-satisfied growing threshold needs no re-check', () {
    expect(
      delayFor(
        rules: [rule()],
        partnerState: charging(const Duration(minutes: 250)),
      ),
      isNull,
    );
  });

  test('a strict threshold is scheduled one instant after the boundary', () {
    expect(
      delayFor(
        rules: [
          rule(
            operator: RuleOperator.greaterThan,
            threshold: const Duration(minutes: 20),
          ),
        ],
        partnerState: charging(const Duration(minutes: 19)),
      ),
      const Duration(minutes: 1, seconds: 1),
    );
  });

  test('a satisfied upper bound is scheduled for when it will stop holding',
      () {
    expect(
      delayFor(
        rules: [
          rule(
            operator: RuleOperator.lessThan,
            threshold: const Duration(minutes: 20),
          ),
        ],
        partnerState: charging(const Duration(minutes: 10)),
      ),
      const Duration(minutes: 10),
    );
  });

  test('an upper bound that can no longer hold is not scheduled', () {
    expect(
      delayFor(
        rules: [
          rule(
            operator: RuleOperator.lessThan,
            threshold: const Duration(minutes: 20),
          ),
        ],
        partnerState: charging(const Duration(minutes: 30)),
      ),
      isNull,
    );
  });

  test('an equality condition on a growing value is left to state changes', () {
    expect(
      delayFor(
        rules: [
          rule(
            operator: RuleOperator.equalTo,
            threshold: const Duration(minutes: 20),
          ),
        ],
        partnerState: charging(const Duration(minutes: 10)),
      ),
      isNull,
    );
  });

  test('a pass that just happened cannot produce a tight retry loop', () {
    final elapsed = const Duration(minutes: 20) - const Duration(milliseconds: 400);
    expect(
      delayFor(
        rules: [rule(threshold: const Duration(minutes: 20))],
        partnerState: charging(elapsed),
      ),
      RuleReevaluationScheduler.minimumDelay,
    );
  });

  test('a distant threshold is bounded rather than scheduled hours ahead', () {
    expect(
      delayFor(
        rules: [rule(threshold: const Duration(hours: 4))],
        partnerState: charging(const Duration(minutes: 1)),
      ),
      RuleReevaluationScheduler.maximumDelay,
    );
  });

  test('one timer serves the earliest crossing across every rule', () {
    expect(
      delayFor(
        rules: [
          rule(id: 'rule-a', name: 'A', threshold: const Duration(minutes: 30)),
          rule(id: 'rule-b', name: 'B', threshold: const Duration(minutes: 15)),
        ],
        partnerState: charging(const Duration(minutes: 5)),
      ),
      const Duration(minutes: 10),
    );
  });

  test('an undecided rule waits for data, not for the clock', () {
    expect(
      delayFor(rules: [rule()], partnerState: testPartnerState()),
      isNull,
    );
  });

  test('offline duration is not planned, because its value is document-bound',
      () {
    // Documented limitation: this figure is measured to the moment the partner
    // published it, so it is re-evaluated on each incoming state update instead.
    expect(
      delayFor(
        rules: [
          rule(
            metric: RuleMetric.offlineDuration,
            threshold: const Duration(minutes: 60),
          ),
        ],
        partnerState: testPartnerState(
          networkStatus: 'offline',
          lastOnlineAt: testNow.subtract(const Duration(minutes: 90)),
        ),
      ),
      isNull,
    );
  });
}
