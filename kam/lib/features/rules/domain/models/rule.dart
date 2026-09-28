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
  networkType,
  internetAvailability,
  networkStatus,
  offlineDuration,
  lastOnlineDuration,
  lastActivityDuration,
  screenState,
  distanceFromHomeKm,
  homePresence,
  locationAvailability,
  locationAge,
  deviceAvailability,
  timeSinceLastAvailability,
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

/// Combines sibling conditions without introducing a general expression
/// language. Conditions in [conditions] are evaluated in their stored order.
class RuleConditionGroup {
  const RuleConditionGroup({required this.operator, required this.conditions});

  final RuleGroupOperator operator;
  final List<RuleCondition> conditions;
}

enum RuleGroupOperator { all, any }

/// A validation problem is safe to show in a rule editor and contains no input
/// data or device identifiers.
class RuleValidationIssue {
  const RuleValidationIssue(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
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
       ),
       assert(
         probabilityPercent == null ||
             (probabilityPercent >= 0 && probabilityPercent <= 100),
         'A user-defined probability must be between 0 and 100',
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
    this.version = 1,
    this.conditionGroup,
    this.enabled = true,
    this.allowStaleData = false,
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

  /// Incremented whenever the saved rule definition changes.
  final int version;

  /// Optional AND/OR group. [condition] remains the single-condition
  /// compatibility form for rules created before grouping was introduced.
  final RuleConditionGroup? conditionGroup;
  final RuleCondition condition;
  final List<RuleAction> actions;

  /// Whether the rule is enabled (FR-034).
  final bool enabled;

  /// Explicit per-rule opt-in for evaluating aged snapshot measurements.
  /// Results still identify every stale input they consumed.
  final bool allowStaleData;

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

  /// Validates persisted or user-created input before evaluation. Keeping this
  /// runtime check is important because constructor asserts are disabled in
  /// release builds and decoded data is not trustworthy by default.
  List<RuleValidationIssue> validate() {
    final issues = <RuleValidationIssue>[];
    if (id.trim().isEmpty) {
      issues.add(
        const RuleValidationIssue('missing_id', 'Rule ID is required.'),
      );
    }
    if (ownerUserId.trim().isEmpty || pairId.trim().isEmpty) {
      issues.add(
        const RuleValidationIssue(
          'missing_scope',
          'Rule owner and pair are required.',
        ),
      );
    }
    if (name.trim().isEmpty) {
      issues.add(
        const RuleValidationIssue('missing_name', 'Rule name is required.'),
      );
    }
    if (version < 1) {
      issues.add(
        const RuleValidationIssue(
          'invalid_version',
          'Rule version must be at least 1.',
        ),
      );
    }
    if (cooldown.isNegative) {
      issues.add(
        const RuleValidationIssue(
          'invalid_cooldown',
          'Cooldown cannot be negative.',
        ),
      );
    }
    final conditions = conditionGroup?.conditions ?? [condition];
    if (conditionGroup != null && conditions.isEmpty) {
      issues.add(
        const RuleValidationIssue(
          'empty_condition_group',
          'A condition group must contain a condition.',
        ),
      );
    }
    for (var index = 0; index < conditions.length; index++) {
      issues.addAll(_validateCondition(conditions[index], index));
    }
    for (final action in actions) {
      if (action.type == RuleActionType.displayProbability &&
          (action.probabilityPercent == null ||
              action.probabilityPercent! < 0 ||
              action.probabilityPercent! > 100)) {
        issues.add(
          const RuleValidationIssue(
            'invalid_probability',
            'User-defined probability must be between 0 and 100.',
          ),
        );
      }
    }
    return List.unmodifiable(issues);
  }

  static List<RuleValidationIssue> _validateCondition(
    RuleCondition condition,
    int index,
  ) {
    final issues = <RuleValidationIssue>[];
    final numeric = condition.numericThreshold;
    final duration = condition.durationThreshold;
    final state = condition.stateValue;
    final durationMetric = {
      RuleMetric.chargingDuration,
      RuleMetric.offlineDuration,
      RuleMetric.lastOnlineDuration,
      RuleMetric.lastActivityDuration,
      RuleMetric.locationAge,
      RuleMetric.timeSinceLastAvailability,
    }.contains(condition.metric);
    final stateMetric = {
      RuleMetric.chargingState,
      RuleMetric.networkType,
      RuleMetric.internetAvailability,
      RuleMetric.screenState,
      RuleMetric.networkStatus,
      RuleMetric.homePresence,
      RuleMetric.locationAvailability,
      RuleMetric.deviceAvailability,
    }.contains(condition.metric);
    final stateOperators = {
      RuleOperator.equalTo,
      RuleOperator.notEqualTo,
      RuleOperator.isA,
      RuleOperator.isNot,
      RuleOperator.hasRemainedInStateFor,
    };
    final prefix = 'condition_${index + 1}';

    if (condition.operator == RuleOperator.hasRemainedInStateFor) {
      if (!stateMetric ||
          state == null ||
          state.trim().isEmpty ||
          (duration == null && numeric == null) ||
          (duration != null && numeric != null)) {
        issues.add(
          RuleValidationIssue(
            'invalid_state_duration',
            '$prefix requires a state metric, state, and one valid duration threshold.',
          ),
        );
      }
    } else if (stateMetric) {
      if (state == null ||
          state.trim().isEmpty ||
          numeric != null ||
          duration != null ||
          !stateOperators.contains(condition.operator)) {
        issues.add(
          RuleValidationIssue(
            'invalid_state_value',
            '$prefix requires a state value only.',
          ),
        );
      } else if (!_validState(condition.metric, state)) {
        issues.add(
          RuleValidationIssue(
            'invalid_state_value',
            '$prefix has an unsupported state for its metric.',
          ),
        );
      }
    } else if (durationMetric) {
      if ((numeric == null) == (duration == null) ||
          state != null ||
          (numeric != null && (!numeric.isFinite || numeric < 0)) ||
          (duration?.isNegative ?? false)) {
        issues.add(
          RuleValidationIssue(
            'invalid_duration_value',
            '$prefix requires one non-negative duration threshold.',
          ),
        );
      }
    } else if (numeric == null ||
        !numeric.isFinite ||
        state != null ||
        duration != null) {
      issues.add(
        RuleValidationIssue(
          'invalid_numeric_value',
          '$prefix requires one finite numeric threshold.',
        ),
      );
    }
    if (condition.metric == RuleMetric.batteryPercentage &&
        numeric != null &&
        (numeric < 0 || numeric > 100)) {
      issues.add(
        RuleValidationIssue(
          'battery_out_of_range',
          '$prefix battery percentage must be 0–100.',
        ),
      );
    }
    return issues;
  }

  static bool _validState(RuleMetric metric, String state) {
    final allowed = switch (metric) {
      RuleMetric.chargingState => {
        'charging',
        'notCharging',
        'fullyCharged',
        'full',
        'discharging',
        'unknown',
      },
      RuleMetric.networkType => {
        'wifi',
        'mobile',
        'ethernet',
        'bluetooth',
        'vpn',
        'none',
        'unknown',
      },
      RuleMetric.internetAvailability => {
        'available',
        'unavailable',
        'unknown',
      },
      RuleMetric.networkStatus => {
        'online',
        'offline',
        'wifi',
        'mobile',
        'unknown',
      },
      RuleMetric.screenState => {'on', 'off', 'unknown'},
      RuleMetric.homePresence => {
        'atHome',
        'nearHome',
        'awayFromHome',
        'stale',
        'unsupported',
        'unknown',
      },
      RuleMetric.locationAvailability => {
        'available',
        'unavailable',
        'unknown',
        'unsupported',
        'permissionDenied',
        'serviceDisabled',
        'error',
        'stale',
      },
      RuleMetric.deviceAvailability => {
        'active',
        'recentlySeen',
        'offline',
        'unknown',
        'available',
        'stale',
        'unsupported',
        'permissionDenied',
        'serviceDisabled',
        'error',
        'unavailable',
      },
      _ => const <String>{},
    };
    return allowed.contains(state);
  }

  @override
  String toString() => 'Rule($id, $name, enabled: $enabled)';
}
