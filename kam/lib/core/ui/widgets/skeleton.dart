import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// A calm placeholder block for content that has not arrived yet.
///
/// Deliberately **not animated**: a pulsing block draws the eye and competes
/// with realtime updates, which is exactly the interruption this redesign is
/// removing. A static muted shape communicates "still arriving" without
/// demanding attention (SRS NFR-025).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadius.sm,
  });

  /// Fixed width, or null to fill the available width.
  final double? width;

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    // A skeleton is decorative: announcing it would only add noise for a screen
    // reader, which is told about the loaded content instead.
    return ExcludeSemantics(child: box);
  }
}

/// A skeleton text line. [widthFactor] is a fraction of the available width so
/// lines look like prose rather than a table.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 0.6, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, width: double.infinity, radius: 6),
    );
  }
}

/// Placeholder for a titled section with a few value rows.
///
/// Mirrors the shape of `SectionCard` so a loading screen keeps the same layout
/// as the loaded one and therefore does not jump when the data arrives. When
/// [title] is given the heading is rendered for real: the user should be able to
/// see what the section *is* while it loads, and the layout must not shift when
/// the value arrives.
class SectionSkeleton extends StatelessWidget {
  const SectionSkeleton({
    super.key,
    this.title,
    this.icon,
    this.rows = 3,
  });

  final String? title;
  final IconData? icon;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
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
                  child: Text(title!, style: theme.textTheme.titleMedium),
                ),
              ],
            )
          else
            const SkeletonLine(widthFactor: 0.35, height: 14),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < rows; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                Expanded(flex: 3, child: SkeletonLine(widthFactor: 0.5)),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: SkeletonLine(widthFactor: 0.8)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
