import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import '../data_presentation_state.dart';

/// Presents a metric that has no value, without ever inventing one.
///
/// This is the widget that guarantees the SRS rule "Battery: Unknown, never
/// Battery: 0%" (FR-048, FR-068, NFR-007). Each non-available state gets its own
/// label and icon so the reason is explicit.
class UnavailableView extends StatelessWidget {
  const UnavailableView({super.key, required this.state, this.compact = false});

  /// One of unknown, unsupported, unavailable or paused.
  final DataPresentationState state;

  /// When true, renders a single compact line suitable for a metric row.
  final bool compact;

  /// Default label for a non-available state.
  static String labelFor(DataPresentationState state) {
    switch (state) {
      case DataPresentationState.unknown:
        return 'Unknown';
      case DataPresentationState.unsupported:
        return 'Not supported on this device';
      case DataPresentationState.unavailable:
        return 'Unavailable';
      case DataPresentationState.paused:
        return 'Sharing paused';
      default:
        return 'Unknown';
    }
  }

  /// Default icon for a non-available state.
  static IconData iconFor(DataPresentationState state) {
    switch (state) {
      case DataPresentationState.unsupported:
        return Icons.block_outlined;
      case DataPresentationState.unavailable:
        return Icons.visibility_off_outlined;
      case DataPresentationState.paused:
        return Icons.pause_circle_outline;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = labelFor(state);

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(state), size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      );
    }

    return Semantics(
      label: label,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconFor(state), size: 36, color: theme.colorScheme.outline),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
