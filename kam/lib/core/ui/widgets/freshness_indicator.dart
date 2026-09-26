import 'package:flutter/material.dart';

import '../../freshness/data_freshness.dart';
import '../../time/date_time_utils.dart';

/// Shows how old a piece of data is, so stale data never looks current
/// (SRS FR-047, FR-061, NFR-025).
///
/// Deliberately text plus icon; colour is only secondary reinforcement so the
/// meaning survives greyscale and colour-blind viewing (NFR-028).
class FreshnessIndicator extends StatelessWidget {
  const FreshnessIndicator({
    super.key,
    required this.freshness,
    this.age,
    this.compact = true,
  });

  /// Freshness classification of the value.
  final DataFreshness freshness;

  /// Age of the value; when null only the classification is shown.
  final Duration? age;

  /// Compact single-line form.
  final bool compact;

  /// Human-readable label for a freshness classification, including age.
  static String labelFor(DataFreshness freshness, Duration? age) {
    final ageText = age == null ? null : DateTimeUtils.formatAge(age);
    switch (freshness) {
      case DataFreshness.fresh:
        return ageText == null ? 'Fresh' : 'Updated $ageText';
      case DataFreshness.recent:
        return ageText == null ? 'Recently updated' : 'Updated $ageText';
      case DataFreshness.stale:
        return ageText == null ? 'Stale' : 'Last updated $ageText';
      case DataFreshness.unknown:
        return 'Update time unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = labelFor(freshness, age);
    final isStale = freshness == DataFreshness.stale;

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isStale ? Icons.history_toggle_off : Icons.schedule,
            size: 14,
            color: isStale
                ? theme.colorScheme.error
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isStale
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
