import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/ui/data_presentation_state.dart';
import '../../../../core/ui/widgets/freshness_indicator.dart';
import '../../../../core/ui/widgets/unavailable_view.dart';
import '../../domain/models/metric_value.dart';

/// One reassurance row: label, value (or an explicit non-available state) and
/// freshness.
///
/// This is where the "never show 0% when the truth is Unknown" rule becomes
/// visible (SRS FR-048, NFR-007). The current time comes from the injected
/// `clockProvider`, so freshness is deterministic in tests.
class MetricTile<T> extends ConsumerWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.format,
  });

  /// Human-readable metric name, for example `Battery`.
  final String label;

  /// Leading icon.
  final IconData icon;

  /// The metric value.
  final MetricValue<T> value;

  /// Optional formatter for the raw value.
  final String Function(T value)? format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).nowUtc();
    final theme = Theme.of(context);

    final presentation = DataPresentation.fromAvailability(
      value.availability,
      freshness: value.freshnessAt(now),
      age: value.ageAt(now),
      hasValue: value.hasValue,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (presentation.hasContent)
                  Text(
                    format?.call(value.value as T) ?? '${value.value}',
                    style: theme.textTheme.titleMedium,
                  )
                else
                  UnavailableView(state: presentation.state, compact: true),
                if (presentation.showsFreshness)
                  FreshnessIndicator(
                    freshness: presentation.freshness!,
                    age: presentation.age,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
