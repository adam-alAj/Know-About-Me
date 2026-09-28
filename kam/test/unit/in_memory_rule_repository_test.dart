import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/rules/data/repositories/in_memory_rule_repository.dart';
import 'package:kam/features/rules/domain/models/rule.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);

  Rule buildRule({
    String id = 'rule-1',
    String ownerUserId = 'user-a',
    String pairId = 'pair-1',
    String name = 'Rule',
    bool enabled = true,
    DateTime? updatedAt,
  }) {
    return Rule(
      id: id,
      ownerUserId: ownerUserId,
      pairId: pairId,
      name: name,
      condition: const RuleCondition(
        metric: RuleMetric.chargingDuration,
        operator: RuleOperator.greaterThanOrEqual,
        durationThreshold: Duration(hours: 4),
      ),
      actions: const [RuleAction(type: RuleActionType.displayStatus)],
      enabled: enabled,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  group('InMemoryRuleRepository', () {
    test('saves and reads back a rule scoped to owner and pair', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(buildRule());

      final rules = await repository.getRules(
        ownerUserId: 'user-a',
        pairId: 'pair-1',
      );
      expect(rules, hasLength(1));
      expect(rules.single.id, 'rule-1');
    });

    test('never returns another owner or another pair', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(buildRule(id: 'mine'));
      await repository.saveRule(
        buildRule(id: 'theirs', ownerUserId: 'user-b'),
      );
      await repository.saveRule(buildRule(id: 'other-pair', pairId: 'pair-2'));

      final rules = await repository.getRules(
        ownerUserId: 'user-a',
        pairId: 'pair-1',
      );
      expect(rules.map((rule) => rule.id), ['mine']);
    });

    test('orders rules newest first', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(
        buildRule(id: 'old', updatedAt: now.subtract(const Duration(days: 1))),
      );
      await repository.saveRule(buildRule(id: 'new', updatedAt: now));

      final rules = await repository.getRules(
        ownerUserId: 'user-a',
        pairId: 'pair-1',
      );
      expect(rules.map((rule) => rule.id), ['new', 'old']);
    });

    test('getRule honours the pair scope', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(buildRule());

      expect(
        await repository.getRule(
          ownerUserId: 'user-a',
          pairId: 'pair-1',
          ruleId: 'rule-1',
        ),
        isNotNull,
      );
      expect(
        await repository.getRule(
          ownerUserId: 'user-a',
          pairId: 'pair-2',
          ruleId: 'rule-1',
        ),
        isNull,
      );
    });

    test('refuses to overwrite an existing rule on save', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(buildRule());

      await expectLater(
        repository.saveRule(buildRule(name: 'Changed')),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('updates an existing rule and rejects a missing one', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(buildRule());

      await repository.updateRule(buildRule(name: 'Renamed'));
      final rules = await repository.getRules(
        ownerUserId: 'user-a',
        pairId: 'pair-1',
      );
      expect(rules.single.name, 'Renamed');

      await expectLater(
        repository.updateRule(buildRule(id: 'missing')),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('deletes a rule and rejects a mismatched pair', () async {
      final repository = InMemoryRuleRepository();
      await repository.saveRule(buildRule());

      await expectLater(
        repository.deleteRule(
          ownerUserId: 'user-a',
          pairId: 'pair-2',
          ruleId: 'rule-1',
        ),
        throwsA(isA<NotFoundFailure>()),
      );
      await repository.deleteRule(
        ownerUserId: 'user-a',
        pairId: 'pair-1',
        ruleId: 'rule-1',
      );
      expect(
        await repository.getRules(ownerUserId: 'user-a', pairId: 'pair-1'),
        isEmpty,
      );
    });

    test('reports itself as ephemeral', () {
      expect(InMemoryRuleRepository().isEphemeral, isTrue);
    });
  });
}
