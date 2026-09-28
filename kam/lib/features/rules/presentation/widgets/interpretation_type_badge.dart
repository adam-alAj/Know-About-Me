import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../domain/rule_draft.dart';

/// Labels which kind of interpretation a rule produced (SRS FR-029).
///
/// The wording is the application's own vocabulary — "Status", "Message" or
/// "User-defined probability" — so a reader can tell that the text beside it was
/// configured by a person rather than measured by the app (STEP 7, STEP 20).
///
/// Meaning is carried by an icon *and* a word, so it survives greyscale,
/// colour-blindness and screen readers (SRS NFR-028).
class InterpretationTypeBadge extends StatelessWidget {
  const InterpretationTypeBadge({super.key, required this.type});

  final RuleOutputKind type;

  static IconData iconFor(RuleOutputKind type) => switch (type) {
    RuleOutputKind.status => Icons.flag_outlined,
    RuleOutputKind.message => Icons.chat_bubble_outline,
    RuleOutputKind.probability => Icons.percent,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A calm, neutral treatment: an ordinary rule match is not an alert
    // (STEP 18).
    final foreground = scheme.onSurfaceVariant;
    final background = scheme.surfaceContainerHighest;

    return Semantics(
      label: 'Interpretation type: ${type.label}',
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
            Icon(iconFor(type), size: 16, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            // Allowed to wrap and then ellipsize: with a large text scale, or a
            // narrow phone, the label must never push its parent over.
            Flexible(
              child: Text(
                type.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
