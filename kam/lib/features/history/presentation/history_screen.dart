import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/empty_view.dart';
import '../../../core/ui/widgets/loading_view.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../pairing/presentation/providers/pairing_providers.dart';
import '../domain/models/device_event.dart';
import 'history_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  EventCategory? _category;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyEventsProvider(_category));
    return AppScaffold(
      title: 'History',
      actions: [
        IconButton(
          tooltip: 'Clear history',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmClear(context),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: AppSpacing.xs, children: [
            _filterChip('All', null),
            for (final category in EventCategory.values)
              _filterChip(_categoryLabel(category), category),
          ]),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: history.when(
            loading: () => const LoadingView(label: 'Loading history'),
            error: (_, _) => const EmptyView(
              icon: Icons.history_outlined,
              title: 'History is unavailable',
              message: 'Your saved history could not be loaded right now.',
            ),
            data: (events) => events.isEmpty
                ? const EmptyView(
                    icon: Icons.history_outlined,
                    title: 'No events yet',
                    message: 'Meaningful device changes and rule transitions will appear here.',
                  )
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) => _EventTile(event: events[index]),
                  ),
          )),
        ],
      ),
    );
  }

  Widget _filterChip(String label, EventCategory? category) => ChoiceChip(
    label: Text(label),
    selected: _category == category,
    onSelected: (_) => setState(() => _category = category),
  );

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This clears saved history from this device and, while connected, your own events in the pair history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final scope = ref.read(partnerScopeProvider).value;
    final uid = ref.read(currentIdentityProvider)?.uid;
    if (scope != null && uid != null) {
      await ref.read(historyRecorderProvider).clear(pairId: scope.pairId, ownerUserId: uid);
    } else {
      await ref.read(localHistoryRepositoryProvider).clearLocal();
    }
    ref.invalidate(historyEventsProvider(_category));
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final DeviceEvent event;

  @override
  Widget build(BuildContext context) {
    final time = event.recordedAt ?? event.occurredAt;
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.history),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.summary ?? _eventLabel(event.type), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text('${time.toLocal()}  ·  ${_categoryLabel(event.category)}'),
        ])),
      ]),
    );
  }
}

String _categoryLabel(EventCategory category) => switch (category) {
  EventCategory.device => 'Device',
  EventCategory.network => 'Network',
  EventCategory.location => 'Location',
  EventCategory.charging => 'Charging',
  EventCategory.rules => 'Rules',
  EventCategory.notifications => 'Notifications',
};

String _eventLabel(DeviceEventType type) => switch (type) {
  DeviceEventType.chargingStarted => 'Charging started',
  DeviceEventType.chargingStopped => 'Charging stopped',
  DeviceEventType.deviceWentOffline => 'Connectivity unavailable',
  DeviceEventType.deviceCameOnline => 'Connectivity available again',
  DeviceEventType.locationChangedSignificantly => 'Location state changed',
  DeviceEventType.ruleActivated => 'A rule matched',
  DeviceEventType.ruleDeactivated => 'A rule no longer matched',
  DeviceEventType.ruleBecameUnknown => 'A rule could not be evaluated',
  DeviceEventType.ruleNotificationGenerated => 'Rule notification shown',
  DeviceEventType.connectionChanged => 'Network connection changed',
  DeviceEventType.sharingPermissionChanged => 'Sharing settings changed',
  DeviceEventType.interpretationGenerated => 'Rule interpretation generated',
  DeviceEventType.notificationSuppressed => 'Rule notification suppressed',
};
