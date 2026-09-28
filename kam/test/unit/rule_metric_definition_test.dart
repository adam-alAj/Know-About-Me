import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/rules/domain/metric_definition.dart';
import 'package:kam/features/rules/domain/models/rule.dart';

void main() {
  Rule ruleWith(RuleCondition condition) => Rule(
    id: 'rule-1',
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    name: 'Test rule',
    condition: condition,
    actions: const <RuleAction>[],
  );

  group('RuleMetrics catalogue', () {
    test('covers every metric the engine can evaluate', () {
      expect(
        RuleMetrics.all.map((definition) => definition.metric).toSet(),
        RuleMetric.values.toSet(),
      );
      expect(RuleMetrics.all, hasLength(RuleMetric.values.length));
      for (final metric in RuleMetric.values) {
        expect(RuleMetrics.of(metric).metric, metric);
      }
    });

    test('every definition offers at least one operator', () {
      for (final definition in RuleMetrics.all) {
        expect(
          definition.allowedOperators,
          isNotEmpty,
          reason: definition.metric.name,
        );
      }
    });

    test('state metrics offer states and no numeric operators', () {
      for (final definition in RuleMetrics.all) {
        if (definition.valueKind != RuleValueKind.state) continue;
        expect(definition.states, isNotEmpty, reason: definition.metric.name);
        expect(
          definition.allowedOperators,
          everyElement(isIn(stateRuleOperators)),
          reason: definition.metric.name,
        );
      }
    });

    test('numeric and duration metrics offer only comparison operators', () {
      for (final definition in RuleMetrics.all) {
        if (definition.valueKind == RuleValueKind.state) continue;
        expect(
          definition.allowedOperators,
          everyElement(isIn(numericRuleOperators)),
          reason: definition.metric.name,
        );
      }
    });

    test('offered states are accepted by the canonical validator', () {
      for (final definition in RuleMetrics.all) {
        if (definition.valueKind != RuleValueKind.state) continue;
        for (final state in definition.states) {
          final issues = ruleWith(
            RuleCondition(
              metric: definition.metric,
              operator: RuleOperator.isA,
              stateValue: state.value,
            ),
          ).validate();
          expect(
            issues,
            isEmpty,
            reason: '${definition.metric.name} / ${state.value} was rejected',
          );
        }
      }
    });

    test('offered operators build conditions the validator accepts', () {
      for (final definition in RuleMetrics.all) {
        for (final operator in definition.allowedOperators) {
          final condition = switch (definition.valueKind) {
            RuleValueKind.state => RuleCondition(
              metric: definition.metric,
              operator: operator,
              stateValue: definition.states.first.value,
            ),
            RuleValueKind.duration => RuleCondition(
              metric: definition.metric,
              operator: operator,
              durationThreshold: const Duration(minutes: 30),
            ),
            RuleValueKind.percentage || RuleValueKind.number => RuleCondition(
              metric: definition.metric,
              operator: operator,
              numericThreshold: 10,
            ),
          };
          expect(
            ruleWith(condition).validate(),
            isEmpty,
            reason: '${definition.metric.name} / ${operator.name} was rejected',
          );
        }
      }
    });

    test('every operator has a plain-language label', () {
      for (final operator in RuleOperator.values) {
        expect(ruleOperatorLabel(operator).trim(), isNotEmpty);
      }
    });
  });
}
