import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// Shared empty-state presentation.
///
/// Distinct from "unknown": empty means the operation succeeded and there is
/// genuinely nothing yet, for example no rules configured (SRS Task 13).
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final String? title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            if (title != null) ...[
              Text(title!, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
