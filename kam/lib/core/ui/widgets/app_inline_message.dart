import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// Tone of an [AppInlineMessage].
enum AppMessageTone {
  /// Neutral information.
  info,

  /// Something needs attention but is not a failure (for example a feature that
  /// is unavailable in this build).
  warning,

  /// A failure with a user-safe explanation.
  error,

  /// A confirmation.
  success,
}

/// Inline message block for form-level feedback.
///
/// Used instead of a snack bar so an error stays on screen while the user
/// corrects the input, and so the message is reachable by assistive technology
/// in place (SRS NFR-028). The tone is always paired with an icon and text —
/// colour is never the only signal.
class AppInlineMessage extends StatelessWidget {
  const AppInlineMessage({
    super.key,
    required this.message,
    this.tone = AppMessageTone.info,
    this.title,
  });

  /// Text to display. Must already be user-safe (comes from `AppFailure.message`
  /// or a fixed string, never from a raw backend exception).
  final String message;

  final AppMessageTone tone;

  /// Optional short heading above [message].
  final String? title;

  static IconData _iconFor(AppMessageTone tone) {
    switch (tone) {
      case AppMessageTone.info:
        return Icons.info_outline;
      case AppMessageTone.warning:
        return Icons.warning_amber_outlined;
      case AppMessageTone.error:
        return Icons.error_outline;
      case AppMessageTone.success:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (foreground, background) = switch (tone) {
      AppMessageTone.info => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
      AppMessageTone.warning => (
        scheme.onErrorContainer,
        scheme.errorContainer,
      ),
      AppMessageTone.error => (scheme.onErrorContainer, scheme.errorContainer),
      AppMessageTone.success => (
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(tone), size: 20, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
