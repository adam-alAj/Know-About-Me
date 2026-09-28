import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/rule.dart';

/// Current stored schema version for a rule document.
const int ruleSchemaVersion = 1;

/// Converts canonical [Rule] values to and from the Firestore document shape
/// defined in `docs/architecture/FIRESTORE_DATA_MODEL.md` §5.
///
/// The document id is never stored inside the document: it is the path segment,
/// so a stored `id` field could disagree with the path. The repository supplies
/// the id when reading.
///
/// Decoding is deliberately defensive. A rule written by an older build, a
/// partially synced document or a hand-edited record must never crash a screen;
/// [ruleFromMap] returns `null` so the caller can report "this rule could not be
/// read" instead of inventing a default (SRS FR-048, NFR-014).
abstract final class RuleSerialization {
  /// Encodes [rule] for storage.
  ///
  /// [isUpdate] omits `createdAt`, so an edit can never move the creation time
  /// (which is also immutable under the Firestore Security Rules).
  static Map<String, dynamic> toMap(Rule rule, {bool isUpdate = false}) {
    return <String, dynamic>{
      'ownerUserId': rule.ownerUserId,
      'pairId': rule.pairId,
      'name': rule.name,
      'version': rule.version,
      'enabled': rule.enabled,
      'allowStaleData': rule.allowStaleData,
      'cooldownSeconds': rule.cooldown.inSeconds,
      'condition': _conditionToMap(rule.condition),
      if (rule.conditionGroup != null)
        'conditionGroup': _groupToMap(rule.conditionGroup!),
      'actions': [for (final action in rule.actions) _actionToMap(action)],
      if (rule.lastTriggeredAt != null)
        'lastTriggeredAt': Timestamp.fromDate(rule.lastTriggeredAt!.toUtc()),
      // Creation and update times are server-authoritative, so a client cannot
      // backdate a rule, and the Security Rules can require
      // `request.resource.data.createdAt == request.time`.
      if (!isUpdate) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': ruleSchemaVersion,
    };
  }

  /// Decodes a stored document. Returns `null` when it cannot be read safely.
  static Rule? ruleFromMap(String id, Map<String, dynamic> data) {
    final ownerUserId = _string(data['ownerUserId']);
    final pairId = _string(data['pairId']);
    final name = _string(data['name']);
    if (ownerUserId == null || pairId == null || name == null) return null;

    final condition = _conditionFromMap(data['condition']);
    if (condition == null) return null;

    final actions = _actionsFromList(data['actions']);
    if (actions == null) return null;

    return Rule(
      id: id,
      ownerUserId: ownerUserId,
      pairId: pairId,
      name: name,
      version: _int(data['version']) ?? 1,
      condition: condition,
      conditionGroup: _groupFromMap(data['conditionGroup']),
      actions: actions,
      enabled: data['enabled'] is bool ? data['enabled'] as bool : true,
      allowStaleData: data['allowStaleData'] == true,
      cooldown: Duration(seconds: _int(data['cooldownSeconds']) ?? 1800),
      lastTriggeredAt: _date(data['lastTriggeredAt']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  static Map<String, dynamic> _conditionToMap(RuleCondition condition) {
    return <String, dynamic>{
      'metric': condition.metric.name,
      'operator': condition.operator.name,
      if (condition.numericThreshold != null)
        'numericThreshold': condition.numericThreshold,
      if (condition.stateValue != null) 'stateValue': condition.stateValue,
      if (condition.durationThreshold != null)
        'durationSeconds': condition.durationThreshold!.inSeconds,
    };
  }

  static RuleCondition? _conditionFromMap(Object? raw) {
    if (raw is! Map) return null;
    final metric = _enumByName(RuleMetric.values, raw['metric']);
    final operator = _enumByName(RuleOperator.values, raw['operator']);
    if (metric == null || operator == null) return null;
    final durationSeconds = _int(raw['durationSeconds']);
    return RuleCondition(
      metric: metric,
      operator: operator,
      numericThreshold: _number(raw['numericThreshold']),
      stateValue: _string(raw['stateValue']),
      durationThreshold: durationSeconds == null
          ? null
          : Duration(seconds: durationSeconds),
    );
  }

  static Map<String, dynamic> _groupToMap(RuleConditionGroup group) {
    return <String, dynamic>{
      'operator': group.operator.name,
      'conditions': [
        for (final condition in group.conditions) _conditionToMap(condition),
      ],
    };
  }

  static RuleConditionGroup? _groupFromMap(Object? raw) {
    if (raw is! Map) return null;
    final operator = _enumByName(RuleGroupOperator.values, raw['operator']);
    final rawConditions = raw['conditions'];
    if (operator == null || rawConditions is! List || rawConditions.isEmpty) {
      return null;
    }
    final conditions = <RuleCondition>[];
    for (final entry in rawConditions) {
      final condition = _conditionFromMap(entry);
      if (condition == null) return null;
      conditions.add(condition);
    }
    return RuleConditionGroup(operator: operator, conditions: conditions);
  }

  static Map<String, dynamic> _actionToMap(RuleAction action) {
    return <String, dynamic>{
      'type': action.type.name,
      if (action.messageTemplate != null)
        'messageTemplate': action.messageTemplate,
      if (action.probabilityPercent != null)
        'probabilityPercent': action.probabilityPercent,
      // A user-configured percentage is always flagged, so it can never be read
      // back as a measured one (SRS FR-030, NFR-023, NFR-041).
      if (action.type == RuleActionType.displayProbability) 'isUserDefined': true,
    };
  }

  static List<RuleAction>? _actionsFromList(Object? raw) {
    if (raw is! List) return null;
    final actions = <RuleAction>[];
    for (final entry in raw) {
      if (entry is! Map) return null;
      final type = _enumByName(RuleActionType.values, entry['type']);
      if (type == null) return null;
      final probability = _int(entry['probabilityPercent']);
      if (type == RuleActionType.displayProbability &&
          (probability == null || probability < 0 || probability > 100)) {
        // A malformed interpretation is not silently repaired.
        return null;
      }
      actions.add(
        RuleAction(
          type: type,
          messageTemplate: _string(entry['messageTemplate']),
          probabilityPercent: probability,
        ),
      );
    }
    return actions;
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _int(Object? raw) => raw is int
      ? raw
      : raw is num
      ? raw.toInt()
      : null;

  static num? _number(Object? raw) => raw is num ? raw : null;

  static DateTime? _date(Object? raw) =>
      raw is Timestamp ? raw.toDate().toUtc() : null;
}
