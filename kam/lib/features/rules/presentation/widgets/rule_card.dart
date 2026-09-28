import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/time/date_time_utils.dart';
import '../../../../core/ui/widgets/app_card.dart';
import '../../domain/models/rule.dart';
import '../../domain/rule_description.dart';
import 'rule_status_badge.dart';

/// One rule in the management list (SRS FR-033).
///
/// Communicates name, enabled state, a concise condition summary and the
/// interpretation. It never shows the rule id, a Firestore path or any other
/// implementation detail (SRS FR-045, NFR-045).
class RuleCard extends StatelessWidget {
  const RuleCard({
    super.key,
    required this.rule,
    required this.onEdit,
    required this.onToggleEnabled,
    required this.onDelete,
    this.busy = false,
  });

  final Rule rule;

  /// Open the rule in the builder.
  final VoidCallback onEdit;

  /// Flip the enabled state.
  final VoidCallback onToggleEnabled;

  /// Delete the rule (the caller confirms first).
  final VoidCallback onDelete;

  /// Whether a write for this rule is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updatedAt = rule.updatedAt;

    return AppCard(
      onTap: busy ? null : onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rule.name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              RuleStatusBadge(enabled: rule.enabled),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _RuleLine(
            label: 'When',
            value: RuleDescription.conditions(rule),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RuleLine(
            label: 'Then',
            value: RuleDescription.interpretation(rule),
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Updated ${DateTimeUtils.formatLocalTimestamp(updatedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const Divider(height: AppSpacing.lg),
          Row(
            children: [
              Text('Use this rule', style: theme.textTheme.bodyMedium),
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                label: rule.enabled
                    ? '${rule.name} is enabled'
                    : '${rule.name} is disabled',
                child: Switch(
                  value: rule.enabled,
                  onChanged: busy ? null : (_) => onToggleEnabled(),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Delete ${rule.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled summary line inside a [RuleCard].
class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
