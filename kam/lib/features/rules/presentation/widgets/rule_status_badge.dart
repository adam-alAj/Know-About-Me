import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';

/// Shows whether a rule is enabled or disabled (SRS FR-034).
///
/// The state is conveyed by an icon *and* the word "Enabled"/"Disabled", so the
/// distinction survives colour-blindness, greyscale and screen readers
/// (SRS NFR-028: never encode meaning in colour alone).
class RuleStatusBadge extends StatelessWidget {
  const RuleStatusBadge({super.key, required this.enabled});

  /// Whether the rule is currently active.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, label, foreground, background) = enabled
        ? (
            Icons.check_circle_outline,
            'Enabled',
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          )
        : (
            Icons.pause_circle_outline,
            'Disabled',
            scheme.onSurfaceVariant,
            scheme.surfaceContainerHighest,
          );

    return Semantics(
      label: enabled ? 'Rule enabled' : 'Rule disabled',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
