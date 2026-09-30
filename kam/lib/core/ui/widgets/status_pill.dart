import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// How much attention a status deserves.
///
/// Tones map onto Material 3 container pairs, so the palette stays correct in
/// any scheme the app is themed with (including a future dark theme) without
/// hard-coded colours. A tone is **never** the only signal: every status in the
/// app also carries an icon and a word, so meaning survives greyscale, colour
/// blindness and screen readers (SRS NFR-028).
enum StatusTone {
  /// Nothing to do: a neutral fact.
  neutral,

  /// Confirmed good.
  positive,

  /// Worth noticing but not a failure — for example "Offline" or "Stale".
  /// Deliberately calmer than [critical] so a dropped connection does not read
  /// as an error the user must fix.
  attention,

  /// A failure, or something the user must act on (a blocked permission).
  critical,
}

/// A compact, calm status statement: icon + word inside a soft container.
///
/// Used for the states the user needs to grasp within seconds — connection,
/// availability, freshness — so those never have to be re-styled per screen.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.icon,
    this.tone = StatusTone.neutral,
    this.semanticLabel,
    this.liveRegion = false,
  });

  /// Short, human-readable state. Never an error code or a backend term.
  final String label;

  /// Reinforces [label]; it never replaces it.
  final IconData icon;

  final StatusTone tone;

  /// Overrides what assistive technology announces, when [label] alone would
  /// lose context (for example "Connection: Offline").
  final String? semanticLabel;

  /// Announces the pill when it appears or changes. Only for statuses that
  /// represent a real transition (a connection dropping), never for static
  /// labels, which would make a screen reader chatter.
  final bool liveRegion;

  /// Foreground/background pair for [tone] in [scheme].
  static (Color, Color) colorsFor(ColorScheme scheme, StatusTone tone) =>
      switch (tone) {
        StatusTone.neutral => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
        ),
        StatusTone.positive => (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        StatusTone.attention => (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
        StatusTone.critical => (
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (foreground, background) = colorsFor(theme.colorScheme, tone);

    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
