import 'metric_definition.dart';
import 'models/rule.dart';

/// What a rule means when it matches (SRS FR-029, FR-030).
///
/// The builder offers only the three interpretation outputs a person authors
/// themselves. Notification and event actions exist on the canonical model but
/// belong to later phases and are never generated here (Phase 16).
enum RuleOutputKind {
  /// A short status, for example "Away from home".
  status,

  /// A sentence, for example "No recent activity was observed".
  message,

  /// A user-defined probability statement, for example a 70% sleep possibility.
  ///
  /// This is never a measured or model-computed probability (FR-030, NFR-023).
  probability;

  /// The canonical action type this output maps to.
  RuleActionType get actionType => switch (this) {
    RuleOutputKind.status => RuleActionType.displayStatus,
    RuleOutputKind.message => RuleActionType.displayMessage,
    RuleOutputKind.probability => RuleActionType.displayProbability,
  };

  /// User-facing label.
  String get label => switch (this) {
    RuleOutputKind.status => 'Status',
    RuleOutputKind.message => 'Message',
    RuleOutputKind.probability => 'User-defined probability',
  };

  /// The canonical output kind for a persisted action, if the builder owns it.
  static RuleOutputKind? fromActionType(RuleActionType type) => switch (type) {
    RuleActionType.displayStatus => RuleOutputKind.status,
    RuleActionType.displayMessage => RuleOutputKind.message,
    RuleActionType.displayProbability => RuleOutputKind.probability,
    _ => null,
  };
}

/// A single condition while it is being edited.
///
/// The threshold is held as *text* on purpose: a draft must be able to represent
/// input that is not yet a number (for example `"hello"`) so validation can
/// report "enter a number" instead of the widget throwing (SRS FR-027, FR-048).
class RuleDraftCondition {
  RuleDraftCondition({
    required this.metric,
    required this.operator,
    this.numericText = '',
    this.stateValue,
    this.durationUnit = DurationUnit.minutes,
    int? key,
  }) : key = key ?? _nextKey++;

  /// Stable identity for widget keys, so removing a condition never shifts the
  /// text fields of the ones that remain.
  final int key;

  final RuleMetric metric;
  final RuleOperator operator;

  /// Raw numeric input for percentage/number/duration metrics.
  final String numericText;

  /// Selected state for state metrics.
  final String? stateValue;

  /// Unit [numericText] is expressed in for duration metrics.
  final DurationUnit durationUnit;

  static int _nextKey = 0;

  RuleMetricDefinition get definition => RuleMetrics.of(metric);

  bool get isState => definition.valueKind == RuleValueKind.state;

  /// A comparable key identifying this condition's *meaning*.
  ///
  /// The threshold is normalised to its canonical form, so `240 minutes` and
  /// `4 hours` produce the same signature — a duplicate check or a saved-rule
  /// comparison must not depend on how a person happened to type the value.
  String get signature {
    final parsed = parseRuleNumber(numericText);
    final value = switch (definition.valueKind) {
      RuleValueKind.state => stateValue ?? '',
      RuleValueKind.duration => parsed == null
          ? numericText.trim()
          : durationUnit.toDuration(parsed).inSeconds.toString(),
      RuleValueKind.percentage || RuleValueKind.number => parsed == null
          ? numericText.trim()
          : formatRuleNumber(parsed),
    };
    return '${metric.name}:${operator.name}:$value';
  }

  RuleDraftCondition copyWith({
    RuleMetric? metric,
    RuleOperator? operator,
    String? numericText,
    String? stateValue,
    bool clearState = false,
    DurationUnit? durationUnit,
  }) {
    return RuleDraftCondition(
      key: key,
      metric: metric ?? this.metric,
      operator: operator ?? this.operator,
      numericText: numericText ?? this.numericText,
      stateValue: clearState ? null : (stateValue ?? this.stateValue),
      durationUnit: durationUnit ?? this.durationUnit,
    );
  }

  /// Validation for one condition. [index] is zero-based and only used to build
  /// a human-readable, non-sensitive message.
  List<RuleValidationIssue> validate(int index) {
    final issues = <RuleValidationIssue>[];
    final prefix = 'Condition ${index + 1}';
    final definition = RuleMetrics.of(metric);

    if (!definition.allowedOperators.contains(operator)) {
      issues.add(
        RuleValidationIssue(
          'invalid_operator',
          '$prefix: that comparison does not apply to ${definition.label.toLowerCase()}.',
        ),
      );
      return issues;
    }

    switch (definition.valueKind) {
      case RuleValueKind.state:
        final state = stateValue;
        if (state == null || state.isEmpty) {
          issues.add(
            RuleValidationIssue('missing_value', '$prefix: choose a value.'),
          );
        } else if (!definition.states.any((option) => option.value == state)) {
          issues.add(
            RuleValidationIssue(
              'invalid_state_value',
              '$prefix: choose a listed value for ${definition.label.toLowerCase()}.',
            ),
          );
        }
      case RuleValueKind.duration:
        final value = parseRuleNumber(numericText);
        if (value == null) {
          issues.add(
            _numericIssue(prefix, numericText),
          );
        } else if (value < 0) {
          issues.add(
            RuleValidationIssue(
              'invalid_duration_value',
              '$prefix: a duration cannot be negative.',
            ),
          );
        }
      case RuleValueKind.percentage:
        final value = parseRuleNumber(numericText);
        if (value == null) {
          issues.add(_numericIssue(prefix, numericText));
        } else if (value < 0 || value > 100) {
          issues.add(
            RuleValidationIssue(
              'battery_out_of_range',
              '$prefix: a percentage must be between 0 and 100.',
            ),
          );
        }
      case RuleValueKind.number:
        final value = parseRuleNumber(numericText);
        if (value == null) {
          issues.add(_numericIssue(prefix, numericText));
        } else if (value < 0) {
          issues.add(
            RuleValidationIssue(
              'invalid_numeric_value',
              '$prefix: enter a value of 0 or more.',
            ),
          );
        }
    }
    return issues;
  }

  static RuleValidationIssue _numericIssue(String prefix, String text) {
    if (text.trim().isEmpty) {
      return RuleValidationIssue('missing_value', '$prefix: enter a value.');
    }
    return RuleValidationIssue(
      'invalid_numeric_value',
      '$prefix: enter a number.',
    );
  }

  /// Converts this condition into the canonical domain representation.
  ///
  /// Call only after [validate] has returned no issues: it parses the threshold
  /// and therefore throws on malformed input by design.
  RuleCondition toCondition() {
    switch (definition.valueKind) {
      case RuleValueKind.state:
        return RuleCondition(
          metric: metric,
          operator: operator,
          stateValue: stateValue,
        );
      case RuleValueKind.duration:
        return RuleCondition(
          metric: metric,
          operator: operator,
          durationThreshold: durationUnit.toDuration(
            parseRuleNumber(numericText)!,
          ),
        );
      case RuleValueKind.percentage:
      case RuleValueKind.number:
        return RuleCondition(
          metric: metric,
          operator: operator,
          numericThreshold: parseRuleNumber(numericText)!,
        );
    }
  }

  static RuleDraftCondition fromCondition(RuleCondition condition) {
    final definition = RuleMetrics.of(condition.metric);
    switch (definition.valueKind) {
      case RuleValueKind.state:
        return RuleDraftCondition(
          metric: condition.metric,
          operator: condition.operator,
          stateValue: condition.stateValue,
        );
      case RuleValueKind.duration:
        final duration =
            condition.durationThreshold ??
            Duration(minutes: (condition.numericThreshold ?? 0).round());
        final inMinutes = duration.inMinutes;
        final useHours = inMinutes >= 60 && inMinutes % 60 == 0;
        return RuleDraftCondition(
          metric: condition.metric,
          operator: condition.operator,
          numericText: useHours
              ? (inMinutes ~/ 60).toString()
              : inMinutes.toString(),
          durationUnit: useHours ? DurationUnit.hours : DurationUnit.minutes,
        );
      case RuleValueKind.percentage:
      case RuleValueKind.number:
        return RuleDraftCondition(
          metric: condition.metric,
          operator: condition.operator,
          numericText: formatRuleNumber(condition.numericThreshold),
        );
    }
  }
}

/// Parses a user-entered number, accepting a comma decimal separator.
num? parseRuleNumber(String text) =>
    num.tryParse(text.trim().replaceAll(',', '.'));

/// Renders a number without a trailing `.0`.
String formatRuleNumber(num? value) {
  if (value == null) return '';
  if (value is int) return value.toString();
  final asDouble = value.toDouble();
  return asDouble == asDouble.roundToDouble()
      ? asDouble.round().toString()
      : asDouble.toString();
}

/// The editable state of a rule (SRS FR-026 – FR-040).
///
/// A draft is the *only* mutable representation of a rule. It is converted into
/// the canonical Phase 13 [Rule] exactly once, after validation, so the builder
/// can never persist a half-formed rule and the engine never sees a second rule
/// model.
class RuleDraft {
  const RuleDraft({
    this.ruleId,
    required this.ownerUserId,
    required this.pairId,
    this.name = '',
    this.groupOperator = RuleGroupOperator.all,
    this.conditions = const <RuleDraftCondition>[],
    this.outputKind = RuleOutputKind.status,
    this.outputText = '',
    this.probabilityText = '',
    this.enabled = true,
    this.cooldownMinutes = 30,
    this.existingVersion,
    this.createdAt,
    this.lastTriggeredAt,
  });

  /// Longest accepted rule name; matches the Firestore Security Rules bound.
  static const int maxNameLength = 120;

  /// Longest accepted interpretation text.
  static const int maxOutputLength = 200;

  /// Existing rule id, or `null` for a rule that has never been saved.
  final String? ruleId;

  final String ownerUserId;
  final String pairId;
  final String name;
  final RuleGroupOperator groupOperator;
  final List<RuleDraftCondition> conditions;
  final RuleOutputKind outputKind;

  /// The interpretation wording (status label, message or probability subject).
  final String outputText;

  /// Raw percentage input, used only when [outputKind] is
  /// [RuleOutputKind.probability].
  final String probabilityText;

  final bool enabled;
  final int cooldownMinutes;

  /// The persisted version when editing; `null` for a new rule.
  final int? existingVersion;

  final DateTime? createdAt;
  final DateTime? lastTriggeredAt;

  /// Whether this draft was loaded from a saved rule.
  bool get isEditing => existingVersion != null;

  /// The version the rule will carry once saved.
  int get nextVersion => (existingVersion ?? 0) + 1;

  /// A new, empty draft bound to the signed-in owner and active pair.
  factory RuleDraft.newRule({
    required String ownerUserId,
    required String pairId,
  }) {
    return RuleDraft(
      ownerUserId: ownerUserId,
      pairId: pairId,
      conditions: [
        RuleDraftCondition(
          metric: RuleMetric.chargingDuration,
          operator: RuleOperator.greaterThanOrEqual,
        ),
      ],
    );
  }

  /// Loads a saved rule into an editable draft.
  factory RuleDraft.fromRule(Rule rule) {
    final conditions = rule.conditionGroup?.conditions ?? [rule.condition];
    final action = rule.actions.isEmpty ? null : rule.actions.first;
    final outputKind = action == null
        ? RuleOutputKind.status
        : (RuleOutputKind.fromActionType(action.type) ?? RuleOutputKind.status);
    return RuleDraft(
      ruleId: rule.id,
      ownerUserId: rule.ownerUserId,
      pairId: rule.pairId,
      name: rule.name,
      groupOperator: rule.conditionGroup?.operator ?? RuleGroupOperator.all,
      conditions: [
        for (final condition in conditions)
          RuleDraftCondition.fromCondition(condition),
      ],
      outputKind: outputKind,
      outputText: action?.messageTemplate ?? '',
      probabilityText: action?.probabilityPercent?.toString() ?? '',
      enabled: rule.enabled,
      cooldownMinutes: rule.cooldown.inMinutes,
      existingVersion: rule.version,
      createdAt: rule.createdAt,
      lastTriggeredAt: rule.lastTriggeredAt,
    );
  }

  RuleDraft copyWith({
    String? ruleId,
    String? ownerUserId,
    String? pairId,
    String? name,
    RuleGroupOperator? groupOperator,
    List<RuleDraftCondition>? conditions,
    RuleOutputKind? outputKind,
    String? outputText,
    String? probabilityText,
    bool? enabled,
    int? cooldownMinutes,
    int? existingVersion,
    DateTime? createdAt,
    DateTime? lastTriggeredAt,
  }) {
    return RuleDraft(
      ruleId: ruleId ?? this.ruleId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      pairId: pairId ?? this.pairId,
      name: name ?? this.name,
      groupOperator: groupOperator ?? this.groupOperator,
      conditions: conditions ?? this.conditions,
      outputKind: outputKind ?? this.outputKind,
      outputText: outputText ?? this.outputText,
      probabilityText: probabilityText ?? this.probabilityText,
      enabled: enabled ?? this.enabled,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      existingVersion: existingVersion ?? this.existingVersion,
      createdAt: createdAt ?? this.createdAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
    );
  }

  /// A deterministic key describing what the rule *does*, independent of its id,
  /// name, enabled flag and timestamps.
  ///
  /// Used for the practical "don't silently create the same rule twice" check
  /// (SRS FR-035). It deliberately compares conditions and interpretation only:
  /// semantic equivalence is not attempted.
  String get behaviourSignature {
    final conditionSignatures = [
      for (final condition in conditions) condition.signature,
    ]..sort();
    return [
      groupOperator.name,
      conditionSignatures.join('&'),
      outputKind.name,
      outputText.trim(),
      outputKind == RuleOutputKind.probability ? probabilityText.trim() : '',
    ].join('|');
  }

  /// The behaviour signature of a persisted rule, for duplicate detection.
  static String behaviourSignatureOf(Rule rule) => RuleDraft.fromRule(
    rule,
  ).behaviourSignature;

  /// Whether the draft defines no conditions at all beyond the required one.
  bool get isEmpty => conditions.isEmpty && name.trim().isEmpty;

  /// Validates the draft in the domain layer (SRS FR-033).
  ///
  /// This runs before persistence and independently of the widgets, so a
  /// malformed rule cannot reach the repository even if a screen forgets a check
  /// (SRS FR-033: "the UI is not the only validation boundary").
  List<RuleValidationIssue> validate() {
    final issues = <RuleValidationIssue>[];

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      issues.add(
        const RuleValidationIssue('missing_name', 'Give the rule a name.'),
      );
    } else if (trimmedName.length > maxNameLength) {
      issues.add(
        const RuleValidationIssue(
          'name_too_long',
          'The rule name is too long.',
        ),
      );
    }

    if (conditions.isEmpty) {
      issues.add(
        const RuleValidationIssue(
          'no_conditions',
          'Add at least one condition.',
        ),
      );
    }

    for (var index = 0; index < conditions.length; index++) {
      issues.addAll(conditions[index].validate(index));
    }

    final seen = <String>{};
    for (final condition in conditions) {
      if (!seen.add(condition.signature)) {
        issues.add(
          const RuleValidationIssue(
            'duplicate_condition',
            'The same condition appears more than once.',
          ),
        );
        break;
      }
    }

    final trimmedOutput = outputText.trim();
    if (trimmedOutput.isEmpty) {
      issues.add(
        const RuleValidationIssue(
          'missing_output',
          'Describe what this rule means when it matches.',
        ),
      );
    } else if (trimmedOutput.length > maxOutputLength) {
      issues.add(
        const RuleValidationIssue(
          'output_too_long',
          'The interpretation text is too long.',
        ),
      );
    }

    if (outputKind == RuleOutputKind.probability) {
      final value = int.tryParse(probabilityText.trim());
      if (value == null) {
        issues.add(
          const RuleValidationIssue(
            'invalid_probability',
            'Enter a whole number for the user-defined probability.',
          ),
        );
      } else if (value < 0 || value > 100) {
        issues.add(
          const RuleValidationIssue(
            'invalid_probability',
            'The user-defined probability must be between 0 and 100.',
          ),
        );
      }
    }

    if (cooldownMinutes < 0) {
      issues.add(
        const RuleValidationIssue(
          'invalid_cooldown',
          'The reminder interval cannot be negative.',
        ),
      );
    }

    return List.unmodifiable(issues);
  }

  /// Whether the draft can be saved.
  bool get isValid => validate().isEmpty;

  /// Converts the draft into the canonical persisted model.
  ///
  /// Call only when [validate] is empty. [id] is supplied by the caller so a new
  /// rule's identifier comes from the repository (never from the UI), and
  /// [nowUtc] comes from the injected clock so timestamps stay deterministic in
  /// tests (NFR-033).
  Rule toRule({required String id, required DateTime nowUtc}) {
    final conditions = [
      for (final condition in this.conditions) condition.toCondition(),
    ];
    final probability = outputKind == RuleOutputKind.probability
        ? int.parse(probabilityText.trim())
        : null;
    return Rule(
      id: id,
      ownerUserId: ownerUserId,
      pairId: pairId,
      name: name.trim(),
      version: nextVersion,
      condition: conditions.first,
      // A single condition keeps the legacy `condition`-only shape; grouping is
      // only materialised when there is more than one, matching Phase 13.
      conditionGroup: conditions.length > 1
          ? RuleConditionGroup(operator: groupOperator, conditions: conditions)
          : null,
      actions: [
        RuleAction(
          type: outputKind.actionType,
          messageTemplate: outputText.trim(),
          probabilityPercent: probability,
        ),
      ],
      enabled: enabled,
      cooldown: Duration(minutes: cooldownMinutes),
      lastTriggeredAt: lastTriggeredAt,
      createdAt: createdAt ?? nowUtc,
      updatedAt: nowUtc,
    );
  }
}
