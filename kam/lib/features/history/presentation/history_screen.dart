import 'package:flutter/material.dart';

import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/empty_view.dart';

/// Placeholder for event history (SRS FR-049 – FR-051).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'History',
      body: EmptyView(
        icon: Icons.history_outlined,
        title: 'No events yet',
        message:
            'Meaningful state changes and rule events will appear here once '
            'device monitoring and synchronization are implemented.',
      ),
    );
  }
}
