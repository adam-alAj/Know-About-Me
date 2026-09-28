import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/ui/widgets/app_card.dart';
import '../../domain/metric_definition.dart';
import '../../domain/models/rule.dart';
import '../../domain/rule_draft.dart';
import 'rule_choice_field.dart';

/// Edits one `metric operator value` condition (SRS FR-026 – FR-032).
///
/// Holds no state: every change is reported to the builder, which owns the draft.
/// The available operators and value editor are derived from the selected
/// metric's [RuleMetricDefinition], so an invalid metric/operator/value
/// combination cannot be assembled in the first place (SRS FR-028, FR-032).
class RuleConditionEditor extends StatelessWidget {
  const RuleConditionEditor({
    super.key,
    required this.condition,
    required this.index,
    required this.canRemove,
    required this.onMetricChanged,
    required this.onChanged,
    required this.onRemove,
    this.errorText,
  });

  /// The condition being edited.
  final RuleDraftCondition condition;

  /// Zero-based position, used only for the heading.
  final int index;

  /// Whether the remove control is available (never for the last condition).
  final bool canRemove;

  /// Metric changed; the builder resets operator/value to match.
  final ValueChanged<RuleMetric> onMetricChanged;

  /// Any other field changed.
  final ValueChanged<RuleDraftCondition> onChanged;

  /// Remove this condition.
  final VoidCallback onRemove;

  /// Validation error for this condition, already user-facing.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definition = condition.definition;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Condition ${index + 1}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: canRemove
                    ? 'Remove condition'
                    : 'A rule needs at least one condition',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: canRemove ? onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RuleChoiceField<RuleMetric>(
            label: 'What to watch',
            value: condition.metric,
            options: [
              for (final option in RuleMetrics.all) (option.metric, option.label),
            ],
            onChanged: onMetricChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          RuleChoiceField<RuleOperator>(
            label: 'Comparison',
            value: condition.operator,
            options: definition.operatorOptions,
            onChanged: (operator) =>
                onChanged(condition.copyWith(operator: operator)),
          ),
          const SizedBox(height: AppSpacing.md),
          _ValueEditor(
            condition: condition,
            index: index,
            onChanged: onChanged,
          ),
          if (definition.platformDependent) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This depends on a capability that may be unavailable on some '
              'devices. When it cannot be observed, the rule reports that it '
              'does not know rather than guessing.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The value control, adapted to the metric's kind (SRS FR-031).
class _ValueEditor extends StatelessWidget {
  const _ValueEditor({
    required this.condition,
    required this.index,
    required this.onChanged,
  });

  final RuleDraftCondition condition;
  final int index;
  final ValueChanged<RuleDraftCondition> onChanged;

  /// Keyed by position and metric so switching metric re-reads the (cleared)
  /// threshold instead of keeping the previous number on screen.
  ValueKey<String> get _valueKey => ValueKey<String>(
    'rule-condition-$index-${condition.metric.name}-value',
  );

  @override
  Widget build(BuildContext context) {
    final definition = condition.definition;

    switch (definition.valueKind) {
      case RuleValueKind.state:
        return RuleChoiceField<String>(
          label: 'Value',
          value: condition.stateValue,
          options: [
            for (final option in definition.states) (option.value, option.label),
          ],
          onChanged: (value) => onChanged(condition.copyWith(stateValue: value)),
        );

      case RuleValueKind.duration:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: _valueKey,
                initialValue: condition.numericText,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'How long',
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) =>
                    onChanged(condition.copyWith(numericText: text)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: RuleChoiceField<DurationUnit>(
                label: 'Unit',
                value: condition.durationUnit,
                options: const [
                  (DurationUnit.minutes, 'minutes'),
                  (DurationUnit.hours, 'hours'),
                ],
                onChanged: (unit) =>
                    onChanged(condition.copyWith(durationUnit: unit)),
              ),
            ),
          ],
        );

      case RuleValueKind.percentage:
      case RuleValueKind.number:
        return TextFormField(
          key: _valueKey,
          initialValue: condition.numericText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Value',
            suffixText: definition.unitLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: (text) => onChanged(condition.copyWith(numericText: text)),
        );
    }
  }
}
