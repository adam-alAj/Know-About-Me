import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// Shared card container used by reassurance panels.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.semanticLabel,
  });

  /// Card content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  /// Optional tap handler; when provided the card becomes interactive.
  final VoidCallback? onTap;

  /// Optional semantic label describing the card as a whole (SRS NFR-028).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    return semanticLabel == null
        ? card
        : Semantics(label: semanticLabel, container: true, child: card);
  }
}
