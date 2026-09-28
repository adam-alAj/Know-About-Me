import '../../../../core/error/app_failure.dart';
import '../../domain/models/rule.dart';
import '../../domain/repositories/rule_repository.dart';

/// [RuleRepository] that keeps rules for the lifetime of the object.
///
/// Used when the build has no reachable account service and by tests. It is not
/// a fake that pretends rules are persisted: it holds them in memory only, and
/// [isEphemeral] records that so the UI can say so honestly rather than implying
/// a rule survived a restart (SRS constraint 10: no fabricated availability).
class InMemoryRuleRepository implements RuleRepository {
  InMemoryRuleRepository({Iterable<Rule> seed = const <Rule>[]}) {
    for (final rule in seed) {
      _rules[_key(rule.ownerUserId, rule.id)] = rule;
    }
  }

  final Map<String, Rule> _rules = <String, Rule>{};

  /// Whether this store forgets its contents when the process ends.
  bool get isEphemeral => true;

  static String _key(String ownerUserId, String ruleId) =>
      '$ownerUserId/$ruleId';

  @override
  Future<List<Rule>> getRules({
    required String ownerUserId,
    required String pairId,
  }) async {
    final rules = <Rule>[
      for (final rule in _rules.values)
        if (rule.ownerUserId == ownerUserId && rule.pairId == pairId) rule,
    ];
    rules.sort((a, b) => _updatedAt(b).compareTo(_updatedAt(a)));
    return rules;
  }

  @override
  Future<Rule?> getRule({
    required String ownerUserId,
    required String pairId,
    required String ruleId,
  }) async {
    final rule = _rules[_key(ownerUserId, ruleId)];
    if (rule == null || rule.pairId != pairId) return null;
    return rule;
  }

  @override
  Future<void> saveRule(Rule rule) async {
    final key = _key(rule.ownerUserId, rule.id);
    if (_rules.containsKey(key)) {
      throw const ValidationFailure('That rule already exists.');
    }
    _rules[key] = rule;
  }

  @override
  Future<void> updateRule(Rule rule) async {
    final key = _key(rule.ownerUserId, rule.id);
    if (_rules[key]?.pairId != rule.pairId) {
      throw const NotFoundFailure('That rule is no longer available.');
    }
    _rules[key] = rule;
  }

  @override
  Future<void> deleteRule({
    required String ownerUserId,
    required String pairId,
    required String ruleId,
  }) async {
    final key = _key(ownerUserId, ruleId);
    if (_rules[key]?.pairId != pairId) {
      throw const NotFoundFailure('That rule is no longer available.');
    }
    _rules.remove(key);
  }

  static DateTime _updatedAt(Rule rule) =>
      rule.updatedAt ??
      rule.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
