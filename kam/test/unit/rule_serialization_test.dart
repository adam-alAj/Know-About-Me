import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/rules/data/rule_serialization.dart';
import 'package:kam/features/rules/domain/models/rule.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);

  Rule sampleRule() => Rule(
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
    cooldown: const Duration(minutes: 30),
    createdAt: now,
    updatedAt: now,
  );

  group('encoding', () {
    test('stores the canonical vocabulary and never the document id', () {
      final map = RuleSerialization.toMap(sampleRule());

      expect(map.containsKey('id'), isFalse);
      expect(map['ownerUserId'], 'user-a');
      expect(map['pairId'], 'pair-1');
      expect(map['name'], 'Long Charging');
      expect(map['version'], 2);
      expect(map['enabled'], isFalse);
      expect(map['cooldownSeconds'], 1800);
      expect(map['schemaVersion'], ruleSchemaVersion);
      final condition = map['condition']! as Map;
      expect(condition['metric'], 'chargingDuration');
      expect(condition['operator'], 'greaterThanOrEqual');
      expect(condition['durationSeconds'], 14400);
    });

    test('flags a user-defined probability', () {
      final action = (RuleSerialization.toMap(sampleRule())['actions']! as List)
          .single as Map;
      expect(action['type'], 'displayProbability');
      expect(action['probabilityPercent'], 70);
      expect(action['isUserDefined'], isTrue);
    });

    test('an update never rewrites the creation timestamp', () {
      final map = RuleSerialization.toMap(sampleRule(), isUpdate: true);
      expect(map.containsKey('createdAt'), isFalse);
      expect(map['updatedAt'], isA<FieldValue>());
    });
  });

  group('decoding', () {
    Map<String, dynamic> validMap() => <String, dynamic>{
      'ownerUserId': 'user-a',
      'pairId': 'pair-1',
      'name': 'Long Charging',
      'version': 3,
      'enabled': true,
      'allowStaleData': false,
      'cooldownSeconds': 900,
      'condition': {
        'metric': 'chargingDuration',
        'operator': 'greaterThanOrEqual',
        'durationSeconds': 14400,
      },
      'actions': [
        {
          'type': 'displayProbability',
          'messageTemplate': 'may be sleeping',
          'probabilityPercent': 70,
          'isUserDefined': true,
        },
      ],
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };

    test('reads a well-formed document', () {
      final rule = RuleSerialization.ruleFromMap('rule-9', validMap());

      expect(rule, isNotNull);
      expect(rule!.id, 'rule-9');
      expect(rule.version, 3);
      expect(rule.enabled, isTrue);
      expect(rule.cooldown, const Duration(minutes: 15));
      expect(rule.condition.durationThreshold, const Duration(hours: 4));
      expect(rule.actions.single.probabilityPercent, 70);
      expect(rule.createdAt, now);
      expect(rule.validate(), isEmpty);
    });

    test('reads a grouped rule', () {
      final map = validMap()
        ..['conditionGroup'] = {
          'operator': 'any',
          'conditions': [
            {
              'metric': 'offlineDuration',
              'operator': 'greaterThanOrEqual',
              'durationSeconds': 3600,
            },
            {
              'metric': 'deviceAvailability',
              'operator': 'isA',
              'stateValue': 'unavailable',
            },
          ],
        };

      final rule = RuleSerialization.ruleFromMap('rule-9', map);
      expect(rule!.conditionGroup, isNotNull);
      expect(rule.conditionGroup!.operator, RuleGroupOperator.any);
      expect(rule.conditionGroup!.conditions, hasLength(2));
      expect(rule.validate(), isEmpty);
    });

    test('skips a malformed stored rule instead of guessing', () {
      expect(
        RuleSerialization.ruleFromMap('r', validMap()..remove('ownerUserId')),
        isNull,
      );
      expect(
        RuleSerialization.ruleFromMap('r', validMap()..remove('name')),
        isNull,
      );
      expect(
        RuleSerialization.ruleFromMap(
          'r',
          validMap()
            ..['condition'] = {
              'metric': 'spaceNetwork',
              'operator': 'isA',
              'stateValue': 'yes',
            },
        ),
        isNull,
      );
      expect(
        RuleSerialization.ruleFromMap('r', validMap()..['actions'] = 'nope'),
        isNull,
      );
      expect(
        RuleSerialization.ruleFromMap(
          'r',
          validMap()
            ..['actions'] = [
              {'type': 'displayProbability'},
            ],
        ),
        isNull,
      );
      expect(
        RuleSerialization.ruleFromMap(
          'r',
          validMap()
            ..['actions'] = [
              {'type': 'displayProbability', 'probabilityPercent': 150},
            ],
        ),
        isNull,
      );
    });

    test('a condition that is not a map is rejected', () {
      expect(
        RuleSerialization.ruleFromMap('r', validMap()..['condition'] = 42),
        isNull,
      );
    });
  });
}
