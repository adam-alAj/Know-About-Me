import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';

/// Shared loading indicator.
///
/// Carries a semantic label so a screen reader announces the wait rather than
/// encountering an unlabelled spinner (SRS NFR-028).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading'});

  /// Text announced to assistive technology and shown below the spinner.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(height: AppSpacing.md),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
