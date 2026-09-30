import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import 'app_card.dart';
import 'status_pill.dart';

/// How prominent a [StateRow]'s value is.
enum StateRowEmphasis {
  /// Supporting information: the value uses the body style.
  normal,

  /// Primary information for the section: the value is slightly stronger.
  strong,
}

/// One labelled value inside a [SectionCard].
///
/// The label is deliberately quieter than the value, so a section can be scanned
/// for states rather than read as a list of pairs. The value is right-aligned,
/// which makes a column of states easy to compare down the screen.
class StateRow extends StatelessWidget {
  const StateRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = StatusTone.neutral,
    this.emphasis = StateRowEmphasis.normal,
  });

  /// What the value describes, for example "Battery".
  final String label;

  /// The state itself, already user-safe and never invented.
  final String value;

  /// Optional reinforcement of [value]. Never the only carrier of meaning.
  final IconData? icon;

  /// Tints the value. Only ever secondary to the text (SRS NFR-028).
  final StatusTone tone;

  final StateRowEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (foreground, _) = StatusPill.colorsFor(theme.colorScheme, tone);
    final useTone = tone != StatusTone.neutral;
    final valueStyle =
        (emphasis == StateRowEmphasis.strong
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyMedium)
            ?.copyWith(color: useTone ? foreground : theme.colorScheme.onSurface);

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (icon != null) ...[
            Icon(icon, size: 16, color: useTone
            ? foreground
            : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled group of related states.
///
/// Replaces one-card-per-fact: related values are grouped so the screen reads as
/// a few meaningful sections instead of a wall of cards, and only sections the
/// partner has actually shared are rendered at all.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.rows,
    this.icon,
    this.subtitle,
    this.footer,
  });

  final String title;
  final List<StateRow> rows;

  /// Meaning carried by the icon is always repeated in [title].
  final IconData? icon;

  /// Optional quiet line under the title, for example where a value comes from.
  final String? subtitle;

  /// Optional action rendered under the rows (for example "Open in Google
  /// Maps"), separated from the values so it never reads as another value.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            rows[index],
          ],
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.md),
            footer!,
          ],
        ],
      ),
    );
  }
}
