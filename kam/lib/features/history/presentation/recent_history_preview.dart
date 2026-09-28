import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/section_header.dart';
import 'history_providers.dart';

/// Bounded dashboard summary; the full timeline stays on the History screen.
class RecentHistoryPreview extends ConsumerWidget {
  const RecentHistoryPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyEventsProvider(null));
    final events = history.value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(
        title: 'Recent activity',
        trailing: TextButton(
          onPressed: () => context.pushNamed(AppRoutes.history),
          child: const Text('View history'),
        ),
      ),
      if (history.isLoading && events.isEmpty)
        const AppCard(child: Text('Loading recent activity'))
      else if (events.isEmpty)
        const AppCard(child: Text('Meaningful device and rule changes will appear here.'))
      else
        AppCard(child: Column(children: [
          for (final event in events.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(children: [
                const Icon(Icons.history, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(event.summary ?? event.type.name)),
              ]),
            ),
        ])),
    ]);
  }
}
