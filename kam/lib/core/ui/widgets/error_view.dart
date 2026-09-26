import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// Shared failure presentation.
///
/// [message] is expected to already be user-safe: it comes from
/// `AppFailure.message`, never from a raw backend exception (SRS NFR-045).
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  /// Safe, human-readable explanation.
  final String message;

  /// Short heading.
  final String title;

  /// Optional retry callback. When null no retry button is shown.
  final VoidCallback? onRetry;

  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon plus text: never colour alone to convey the problem (NFR-028).
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
