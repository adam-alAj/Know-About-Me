import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/rules/domain/metric_definition.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_draft.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);

  RuleDraft buildDraft({
    String name = 'A rule',
    List<RuleDraftCondition>? conditions,
    RuleGroupOperator groupOperator = RuleGroupOperator.all,
    RuleOutputKind outputKind = RuleOutputKind.status,
    String outputText = 'Away from home',
    String probabilityText = '',
    bool enabled = true,
    int? existingVersion,
    DateTime? createdAt,
    DateTime? lastTriggeredAt,
  }) {
    return RuleDraft(
      ownerUserId: 'user-a',
      pairId: 'pair-1',
      name: name,
      groupOperator: groupOperator,
      conditions:
          conditions ??
          [
            RuleDraftCondition(
              metric: RuleMetric.chargingDuration,
              operator: RuleOperator.greaterThanOrEqual,
              numericText: '240',
            ),
          ],
      outputKind: outputKind,
      outputText: outputText,
      probabilityText: probabilityText,
      enabled: enabled,
      existingVersion: existingVersion,
      createdAt: createdAt,
      lastTriggeredAt: lastTriggeredAt,
    );
  }

  Set<String> codes(RuleDraft draft) =>
      draft.validate().map((issue) => issue.code).toSet();

  group('required scenarios', () {
    test('Rule A: long charging with a user-defined sleep probability', () {
      final draft = buildDraft(
        name: 'Long Charging',
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.chargingDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '240',
          ),
        ],
        outputKind: RuleOutputKind.probability,
        outputText: 'may be sleeping',
        probabilityText: '70',
      );

      expect(draft.validate(), isEmpty);
    });

    test('Rule B: offline for one hour with a status output', () {
      final draft = buildDraft(
        name: 'Offline For One Hour',
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.offlineDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '60',
          ),
        ],
        outputKind: RuleOutputKind.status,
        outputText: 'Offline for more than one hour',
      );

      expect(draft.validate(), isEmpty);
    });

    test('Rule C: distance from home with a status output', () {
      final draft = buildDraft(
        name: 'Away From Home',
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.distanceFromHomeKm,
            operator: RuleOperator.greaterThan,
            numericText: '5',
          ),
        ],
        outputKind: RuleOutputKind.status,
        outputText: 'Away from home',
      );

      expect(draft.validate(), isEmpty);
    });

    test('invalid: battery percentage above 100', () {
      final draft = buildDraft(
        name: 'Battery',
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.batteryPercentage,
            operator: RuleOperator.greaterThan,
            numericText: '150',
          ),
        ],
      );

      expect(codes(draft), contains('battery_out_of_range'));
    });

    test('invalid: a non-numeric distance threshold', () {
      final draft = buildDraft(
        name: 'Away',
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.distanceFromHomeKm,
            operator: RuleOperator.greaterThan,
            numericText: 'hello',
          ),
        ],
      );

      expect(codes(draft), contains('invalid_numeric_value'));
    });

    test('invalid: probability above 100', () {
      final draft = buildDraft(
        outputKind: RuleOutputKind.probability,
        outputText: 'may be sleeping',
        probabilityText: '150',
      );

      expect(codes(draft), contains('invalid_probability'));
    });

    test('invalid: no conditions', () {
      final draft = buildDraft(conditions: const <RuleDraftCondition>[]);

      expect(codes(draft), contains('no_conditions'));
    });
  });

  group('name validation', () {
    test('rejects an empty and a whitespace-only name', () {
      expect(codes(buildDraft(name: '')), contains('missing_name'));
      expect(codes(buildDraft(name: '   ')), contains('missing_name'));
    });

    test('rejects an excessively long name', () {
      final draft = buildDraft(name: 'a' * (RuleDraft.maxNameLength + 1));
      expect(codes(draft), contains('name_too_long'));
    });

    test('trims the saved name', () {
      final rule = buildDraft(name: '  Long Charging  ').toRule(
        id: 'r1',
        nowUtc: now,
      );
      expect(rule.name, 'Long Charging');
    });
  });

  group('condition validation', () {
    test('rejects a state metric without a value', () {
      final draft = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.chargingState,
            operator: RuleOperator.isA,
          ),
        ],
      );
      expect(codes(draft), contains('missing_value'));
    });

    test('rejects a state outside the closed vocabulary', () {
      final draft = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.chargingState,
            operator: RuleOperator.isA,
            stateValue: 'sleeping',
          ),
        ],
      );
      expect(codes(draft), contains('invalid_state_value'));
    });

    test('rejects an operator that does not apply to the metric', () {
      final draft = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.chargingState,
            operator: RuleOperator.greaterThan,
            stateValue: 'charging',
          ),
        ],
      );
      expect(codes(draft), contains('invalid_operator'));
    });

    test('rejects a missing and a negative duration threshold', () {
      expect(
        codes(
          buildDraft(
            conditions: [
              RuleDraftCondition(
                metric: RuleMetric.offlineDuration,
                operator: RuleOperator.greaterThanOrEqual,
              ),
            ],
          ),
        ),
        contains('missing_value'),
      );
      expect(
        codes(
          buildDraft(
            conditions: [
              RuleDraftCondition(
                metric: RuleMetric.offlineDuration,
                operator: RuleOperator.greaterThanOrEqual,
                numericText: '-5',
              ),
            ],
          ),
        ),
        contains('invalid_duration_value'),
      );
    });

    test('rejects the same condition twice', () {
      final draft = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.offlineDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '60',
          ),
          RuleDraftCondition(
            metric: RuleMetric.offlineDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '60',
          ),
        ],
      );
      expect(codes(draft), contains('duplicate_condition'));
    });

    test('accepts a comma decimal separator', () {
      final draft = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.distanceFromHomeKm,
            operator: RuleOperator.greaterThan,
            numericText: '5,5',
          ),
        ],
      );
      expect(draft.validate(), isEmpty);
    });
  });

  group('interpretation validation', () {
    test('requires interpretation text', () {
      expect(codes(buildDraft(outputText: '   ')), contains('missing_output'));
    });

    test('accepts the probability boundaries', () {
      for (final value in ['0', '100']) {
        final draft = buildDraft(
          outputKind: RuleOutputKind.probability,
          outputText: 'may be sleeping',
          probabilityText: value,
        );
        expect(draft.validate(), isEmpty, reason: value);
      }
    });

    test('rejects a non-numeric probability', () {
      final draft = buildDraft(
        outputKind: RuleOutputKind.probability,
        outputText: 'may be sleeping',
        probabilityText: 'often',
      );
      expect(codes(draft), contains('invalid_probability'));
    });
  });

  group('canonical conversion', () {
    test('normalises hours into a Duration', () {
      final rule = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.chargingDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '4',
            durationUnit: DurationUnit.hours,
          ),
        ],
      ).toRule(id: 'r1', nowUtc: now);

      expect(rule.condition.durationThreshold, const Duration(hours: 4));
      expect(rule.condition.numericThreshold, isNull);
    });

    test('a single condition keeps the legacy condition-only shape', () {
      final rule = buildDraft().toRule(id: 'r1', nowUtc: now);
      expect(rule.conditionGroup, isNull);
    });

    test('multiple conditions become an AND/OR group', () {
      final rule = buildDraft(
        groupOperator: RuleGroupOperator.any,
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.offlineDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '60',
          ),
          RuleDraftCondition(
            metric: RuleMetric.deviceAvailability,
            operator: RuleOperator.isA,
            stateValue: 'unavailable',
          ),
        ],
        outputText: 'No recent activity',
      ).toRule(id: 'r1', nowUtc: now);

      expect(rule.conditionGroup, isNotNull);
      expect(rule.conditionGroup!.operator, RuleGroupOperator.any);
      expect(rule.conditionGroup!.conditions, hasLength(2));
      expect(rule.validate(), isEmpty);
    });

    test('a user-defined probability action is flagged', () {
      final rule = buildDraft(
        outputKind: RuleOutputKind.probability,
        outputText: 'may be sleeping',
        probabilityText: '70',
      ).toRule(id: 'r1', nowUtc: now);

      final action = rule.actions.single;
      expect(action.type, RuleActionType.displayProbability);
      expect(action.probabilityPercent, 70);
      expect(action.messageTemplate, 'may be sleeping');
    });

    test('a new rule starts at version 1 and an edit increments it', () {
      expect(buildDraft().toRule(id: 'r1', nowUtc: now).version, 1);
      expect(
        buildDraft(existingVersion: 3).toRule(id: 'r1', nowUtc: now).version,
        4,
      );
    });

    test('editing preserves identity, creation time and trigger time', () {
      final createdAt = now.subtract(const Duration(days: 3));
      final lastTriggeredAt = now.subtract(const Duration(hours: 1));
      final rule = buildDraft(
        name: 'Long Charging',
        existingVersion: 2,
        createdAt: createdAt,
        lastTriggeredAt: lastTriggeredAt,
      ).toRule(id: 'rule-7', nowUtc: now);

      expect(rule.id, 'rule-7');
      expect(rule.createdAt, createdAt);
      expect(rule.lastTriggeredAt, lastTriggeredAt);
      expect(rule.updatedAt, now);
    });

    test('enabled state is carried into the canonical rule', () {
      expect(buildDraft(enabled: false).toRule(id: 'r1', nowUtc: now).enabled, isFalse);
    });

    test('cooldown is carried in minutes', () {
      final rule = buildDraft().copyWith(cooldownMinutes: 60).toRule(
        id: 'r1',
        nowUtc: now,
      );
      expect(rule.cooldown, const Duration(minutes: 60));
    });
  });

  group('draft loading', () {
    test('round-trips a canonical rule', () {
      final rule = Rule(
        id: 'rule-1',
        ownerUserId: 'user-a',
        pairId: 'pair-1',
        name: 'Long Charging',
        version: 2,
        condition: const RuleCondition(
          metric: RuleMetric.chargingDuration,
          operator: RuleOperator.greaterThanOrEqual,
          durationThreshold: Duration(hours: 4),
        ),
        actions: const [
          RuleAction(
            type: RuleActionType.displayProbability,
            messageTemplate: 'may be sleeping',
            probabilityPercent: 70,
          ),
        ],
        enabled: false,
        cooldown: const Duration(minutes: 60),
        createdAt: now,
        updatedAt: now,
      );

      final draft = RuleDraft.fromRule(rule);

      expect(draft.ruleId, 'rule-1');
      expect(draft.name, 'Long Charging');
      expect(draft.conditions.single.metric, RuleMetric.chargingDuration);
      expect(draft.conditions.single.numericText, '4');
      expect(draft.conditions.single.durationUnit, DurationUnit.hours);
      expect(draft.outputKind, RuleOutputKind.probability);
      expect(draft.outputText, 'may be sleeping');
      expect(draft.probabilityText, '70');
      expect(draft.enabled, isFalse);
      expect(draft.cooldownMinutes, 60);
      expect(draft.existingVersion, 2);
      expect(draft.isEditing, isTrue);

      final rebuilt = draft.toRule(id: rule.id, nowUtc: now);
      expect(rebuilt.id, rule.id);
      expect(rebuilt.version, 3);
      expect(rebuilt.condition.durationThreshold, const Duration(hours: 4));
      expect(rebuilt.actions.single.probabilityPercent, 70);
    });

    test('a loaded group keeps its operator and condition count', () {
      final rule = Rule(
        id: 'rule-2',
        ownerUserId: 'user-a',
        pairId: 'pair-1',
        name: 'Grouped',
        condition: const RuleCondition(
          metric: RuleMetric.offlineDuration,
          operator: RuleOperator.greaterThanOrEqual,
          durationThreshold: Duration(minutes: 60),
        ),
        conditionGroup: const RuleConditionGroup(
          operator: RuleGroupOperator.any,
          conditions: [
            RuleCondition(
              metric: RuleMetric.offlineDuration,
              operator: RuleOperator.greaterThanOrEqual,
              durationThreshold: Duration(minutes: 60),
            ),
            RuleCondition(
              metric: RuleMetric.deviceAvailability,
              operator: RuleOperator.isA,
              stateValue: 'unavailable',
            ),
          ],
        ),
        actions: const [RuleAction(type: RuleActionType.displayStatus)],
      );

      final draft = RuleDraft.fromRule(rule);

      expect(draft.groupOperator, RuleGroupOperator.any);
      expect(draft.conditions, hasLength(2));
      expect(draft.conditions[1].stateValue, 'unavailable');
    });
  });

  group('duplicate detection', () {
    test('signature ignores the name but not the meaning', () {
      final first = buildDraft(name: 'Long Charging');
      final renamed = buildDraft(name: 'Charging for a long time');
      final different = buildDraft(name: 'Long Charging', outputText: 'Elsewhere');

      expect(first.behaviourSignature, renamed.behaviourSignature);
      expect(first.behaviourSignature, isNot(different.behaviourSignature));
    });

    test('signature is order-independent for AND/OR conditions', () {
      final a = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.offlineDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '60',
          ),
          RuleDraftCondition(
            metric: RuleMetric.batteryPercentage,
            operator: RuleOperator.lessThan,
            numericText: '20',
          ),
        ],
      );
      final b = buildDraft(
        conditions: [
          RuleDraftCondition(
            metric: RuleMetric.batteryPercentage,
            operator: RuleOperator.lessThan,
            numericText: '20',
          ),
          RuleDraftCondition(
            metric: RuleMetric.offlineDuration,
            operator: RuleOperator.greaterThanOrEqual,
            numericText: '60',
          ),
        ],
      );
      expect(a.behaviourSignature, b.behaviourSignature);
    });

    test('a persisted rule has the same signature as its draft', () {
      final draft = buildDraft(
        outputKind: RuleOutputKind.probability,
        outputText: 'may be sleeping',
        probabilityText: '70',
      );
      final rule = draft.toRule(id: 'r1', nowUtc: now);
      expect(RuleDraft.behaviourSignatureOf(rule), draft.behaviourSignature);
    });
  });
}
