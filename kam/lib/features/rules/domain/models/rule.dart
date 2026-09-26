/// Domain model for the user-defined rule engine (SRS FR-026 – FR-040).
library;

/// The observable metrics a rule may reference (SRS FR-027).
///
/// The set is intentionally closed for now and extended additively; NFR-040
/// requires that adding metrics must not force a redesign.
enum RuleMetric {
  batteryPercentage,
  chargingState,
  chargingDuration,
  networkStatus,
  offlineDuration,
  lastOnlineDuration,
  lastActivityDuration,
  distanceFromHomeKm,
  homePresence,
  locationAvailability,
  locationAge,
  deviceAvailability,
}

/// Comparison operators supported by the rule engine (SRS FR-028).
enum RuleOperator {
  equalTo,
  notEqualTo,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  isA,
  isNot,

  /// `has remained in state for` — a duration condition on a state metric.
  hasRemainedInStateFor,
}

/// A single `metric operator threshold` condition (SRS FR-026, FR-032).
class RuleCondition {
  const RuleCondition({
    required this.metric,
    required this.operator,
    this.numericThreshold,
    this.stateValue,
    this.durationThreshold,
  });

  final RuleMetric metric;
  final RuleOperator operator;

  /// Threshold for numeric metrics, for example `240` minutes.
  final num? numericThreshold;

  /// Expected state name for state metrics, for example `charging`.
  final String? stateValue;

  /// Duration for [RuleOperator.hasRemainedInStateFor].
  final Duration? durationThreshold;

  @override
  String toString() =>
      'RuleCondition(${metric.name} ${operator.name} '
      '${numericThreshold ?? stateValue ?? durationThreshold})';
}

/// What a rule produces when its condition becomes active (SRS FR-029).
enum RuleActionType {
  displayMessage,
  displayStatus,
  displayProbability,
  triggerNotification,
  changeReassuranceIndicator,
  createEventRecord,
}

/// A single output of a rule.
class RuleAction {
  const RuleAction({
    required this.type,
    this.messageTemplate,
    this.probabilityPercent,
  }) : assert(
         type != RuleActionType.displayProbability ||
             probabilityPercent != null,
         'A probability action requires a user-configured percentage (FR-030)',
       );

  final RuleActionType type;

  /// Template text. May contain `{partnerName}` for FR-031. Localizable
  /// (NFR-027), so raw user-facing strings are not finalised here.
  final String? messageTemplate;

  /// The user's own configured percentage for [RuleActionType.displayProbability].
  ///
  /// This is a user-defined interpretation and must never be described as a
  /// measured or ML-computed probability (FR-030, NFR-023).
  final int? probabilityPercent;

  @override
  String toString() => 'RuleAction(${type.name}, $messageTemplate)';
}

/// A user-defined `IF condition THEN actions` rule (SRS FR-026 – FR-036).
class Rule {
  const Rule({
    required this.id,
    required this.ownerUserId,
    required this.pairId,
    required this.name,
    required this.condition,
    required this.actions,
    this.enabled = true,
    this.cooldown = const Duration(minutes: 30),
    this.lastTriggeredAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// The user who created the rule (and therefore sees the interpretation).
  final String ownerUserId;

  /// The pair whose partner's device state the rule is evaluated against.
  final String pairId;

  final String name;
  final RuleCondition condition;
  final List<RuleAction> actions;

  /// Whether the rule is enabled (FR-034).
  final bool enabled;

  /// Minimum interval between notifications for a continuously active rule
  /// (FR-039, FR-040).
  final Duration cooldown;

  /// When the rule last produced a notification, in UTC.
  final DateTime? lastTriggeredAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the cooldown allows a new notification at [now] (FR-039).
  bool isCoolingDownAt(DateTime now) {
    final last = lastTriggeredAt;
    if (last == null) return false;
    return now.toUtc().difference(last.toUtc()) < cooldown;
  }

  @override
  String toString() => 'Rule($id, $name, enabled: $enabled)';
}
