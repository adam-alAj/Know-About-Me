import 'metric_definition.dart';
import 'models/rule.dart';
import 'rule_draft.dart';

/// Renders a rule in plain, user-facing language (SRS FR-032, FR-045).
///
/// Pure functions over the canonical model: no widget, no Firestore, no device
/// identifier. Both the rule list and the builder use them, so a rule reads the
/// same wherever it appears, and the wording can be unit-tested directly.
abstract final class RuleDescription {
  /// A short, human-readable phrase for one condition, for example
  /// `Charging duration is at least 4 hours`.
  static String condition(RuleCondition condition) {
    final definition = RuleMetrics.of(condition.metric);
    final operator = ruleOperatorLabel(condition.operator);
    switch (definition.valueKind) {
      case RuleValueKind.state:
        final state = definition.labelForState(condition.stateValue ?? '');
        return '${definition.label} $operator ${state.toLowerCase()}';
      case RuleValueKind.duration:
        final duration =
            condition.durationThreshold ??
            Duration(minutes: (condition.numericThreshold ?? 0).round());
        return '${definition.label} $operator ${formatDuration(duration)}';
      case RuleValueKind.percentage:
        return '${definition.label} $operator '
            '${formatRuleNumber(condition.numericThreshold)}'
            '${definition.unitLabel ?? ''}';
      case RuleValueKind.number:
        final unit = definition.unitLabel;
        return '${definition.label} $operator '
            '${formatRuleNumber(condition.numericThreshold)}'
            '${unit == null ? '' : ' $unit'}';
    }
  }

  /// The conditions of [rule] joined by "and"/"or" (SRS FR-032).
  static String conditions(Rule rule) {
    final group = rule.conditionGroup;
    final conditions = group?.conditions ?? [rule.condition];
    final joiner = group?.operator == RuleGroupOperator.any ? ' or ' : ' and ';
    if (conditions.isEmpty) return 'No conditions';
    return conditions.map(condition).join(joiner);
  }

  /// The meaning of [rule] when it matches.
  ///
  /// A configured percentage is always labelled "user-defined", never presented
  /// as a measurement (SRS FR-030, NFR-023, NFR-041).
  static String interpretation(Rule rule) {
    final action = rule.actions.isEmpty ? null : rule.actions.first;
    if (action == null) return 'No interpretation yet';
    final text = action.messageTemplate?.trim() ?? '';
    switch (action.type) {
      case RuleActionType.displayProbability:
        final percent = action.probabilityPercent;
        final label = percent == null
            ? 'User-defined probability'
            : 'User-defined $percent% probability';
        return text.isEmpty ? label : '$label: $text';
      case RuleActionType.displayStatus:
        return text.isEmpty ? 'Status' : 'Status: $text';
      case RuleActionType.displayMessage:
        return text.isEmpty ? 'Message' : text;
      case RuleActionType.triggerNotification:
      case RuleActionType.changeReassuranceIndicator:
      case RuleActionType.createEventRecord:
        return text.isEmpty ? 'Interpretation' : text;
    }
  }

  /// Whether the rule names a user-defined probability.
  static bool hasUserDefinedProbability(Rule rule) => rule.actions.any(
    (action) => action.type == RuleActionType.displayProbability,
  );

  /// A calm, one-line explanation of what enabling/disabling means.
  static String enabledExplanation(Rule rule) => rule.enabled
      ? 'This rule can be used when the app interprets device state.'
      : 'This rule is saved but will not be used.';

  /// Formats a duration for a person, for example `4 hours` or `1 h 30 min`.
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 1) return 'less than a minute';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) return hours == 1 ? '1 hour' : '$hours hours';
    return '$hours h $remainder min';
  }
}

/// Convenience alias so call sites read naturally.
String describeRuleCondition(RuleCondition condition) =>
    RuleDescription.condition(condition);

/// Formats a duration for a person.
String formatRuleDuration(Duration duration) =>
    RuleDescription.formatDuration(duration);
