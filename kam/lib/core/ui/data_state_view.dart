import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import 'data_presentation_state.dart';
import 'widgets/empty_view.dart';
import 'widgets/error_view.dart';
import 'widgets/freshness_indicator.dart';
import 'widgets/loading_view.dart';
import 'widgets/unavailable_view.dart';

/// Renders a [DataPresentation] exhaustively.
///
/// Every screen that shows remotely observed data should go through this widget
/// so that loading, failure, empty, unknown, unsupported, unavailable and paused
/// states are handled once, correctly, instead of being forgotten per screen.
class DataStateView extends StatelessWidget {
  const DataStateView({
    super.key,
    required this.presentation,
    required this.loadedBuilder,
    this.emptyBuilder,
    this.onRetry,
    this.loadingLabel = 'Loading',
  });

  /// The resolved presentation state.
  final DataPresentation presentation;

  /// Builds the content when a real value exists.
  final WidgetBuilder loadedBuilder;

  /// Optional custom empty content.
  final WidgetBuilder? emptyBuilder;

  /// Passed to [ErrorView] so a failure can be retried.
  final VoidCallback? onRetry;

  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    return switch (presentation.state) {
      DataPresentationState.loading => LoadingView(label: loadingLabel),
      DataPresentationState.failure => ErrorView(
        message: presentation.message ?? 'Please try again.',
        onRetry: onRetry,
      ),
      DataPresentationState.empty =>
        emptyBuilder?.call(context) ??
            const EmptyView(message: 'Nothing here yet.'),
      DataPresentationState.unknown ||
      DataPresentationState.unsupported ||
      DataPresentationState.unavailable ||
      DataPresentationState.paused => UnavailableView(
        state: presentation.state,
      ),
      DataPresentationState.loaded => _LoadedContent(
        presentation: presentation,
        builder: loadedBuilder,
      ),
    };
  }
}

/// Renders loaded content plus its freshness caption, when known.
class _LoadedContent extends StatelessWidget {
  const _LoadedContent({required this.presentation, required this.builder});

  final DataPresentation presentation;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final content = builder(context);
    if (!presentation.showsFreshness) return content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FreshnessIndicator(
          freshness: presentation.freshness!,
          age: presentation.age,
        ),
        const SizedBox(height: AppSpacing.sm),
        content,
      ],
    );
  }
}
