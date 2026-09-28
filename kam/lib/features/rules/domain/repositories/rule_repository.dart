import '../models/rule.dart';

/// Persistence boundary for a user's rules.
///
/// Implementations must scope every operation to the authenticated owner and
/// active pair. The rule engine never performs repository or Firebase I/O.
abstract interface class RuleRepository {
  Future<List<Rule>> getRules({
    required String ownerUserId,
    required String pairId,
  });

  Future<Rule?> getRule({
    required String ownerUserId,
    required String pairId,
    required String ruleId,
  });

  Future<void> saveRule(Rule rule);

  Future<void> updateRule(Rule rule);

  Future<void> deleteRule({
    required String ownerUserId,
    required String pairId,
    required String ruleId,
  });
}
