import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/freshness/data_freshness.dart';
import '../../../../core/ui/widgets/section_card.dart';
import '../../../../core/ui/widgets/skeleton.dart';
import '../../domain/models/activity_state.dart';
import '../../domain/models/state_observation.dart';
import '../providers/device_state_providers.dart';

/// A concise rendering of this device's screen and activity.
///
/// Only information the user can act on is shown: the display state, the
/// activity signal and when a signal was last observed. Technical detail
/// (lifecycle phase, freshness classification, capability lines) is not shown —
/// it stays available in the underlying observations for the rules engine and
/// the logs. Stale, unknown and unsupported states are still spelled out rather
/// than hidden.
class ActivitySummaryCard extends ConsumerWidget {
  const ActivitySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).nowUtc();
    final activityAsync = ref.watch(currentLocalActivityStateProvider);

    if (activityAsync.hasError) {
      return const SectionCard(
        title: 'Screen and activity',
        icon: Icons.phone_android_outlined,
        rows: [
          StateRow(label: 'Status', value: 'Temporarily unavailable'),
        ],
      );
    }
    final state = activityAsync.value;
    if (state == null) {
      return const SectionSkeleton(
        title: 'Screen and activity',
        icon: Icons.phone_android_outlined,
        rows: 3,
      );
    }

    return SectionCard(
      title: 'Screen and activity',
      icon: Icons.phone_android_outlined,
      rows: [
        StateRow(
          label: 'Screen',
          value: _screenLabel(state.screenState),
          emphasis: StateRowEmphasis.strong,
        ),
        StateRow(
          label: 'Activity',
          value: _statusLabel(state.activityStatus),
        ),
        StateRow(
          label: 'Last observed activity',
          value: _lastActivityLabel(state.lastObservedActivityAt, now),
        ),
      ],
    );
  }

  static String _screenLabel(StateObservation<DeviceScreenState> observation) {
    final value = observation.value;
    if (observation.availability == CapabilityAvailability.available &&
        value != null) {
      return switch (value) {
        DeviceScreenState.on => 'On',
        DeviceScreenState.off => 'Off',
        DeviceScreenState.unknown => 'Unknown',
      };
    }
    return _stateLabel(observation.availability);
  }

  static String _statusLabel(StateObservation<ActivityStatus> observation) {
    final value = observation.value;
    if (observation.availability == CapabilityAvailability.available &&
        value != null) {
      return switch (value) {
        ActivityStatus.activityDetected => 'Detected',
        ActivityStatus.noActivityObserved => 'None observed',
        ActivityStatus.unknown => 'Unknown',
      };
    }
    return _stateLabel(observation.availability);
  }

  static String _lastActivityLabel(DateTime? timestamp, DateTime now) {
    if (timestamp == null) return 'None yet';
    final age = now.toUtc().difference(timestamp.toUtc());
    final stale =
        FreshnessPolicy.standard.classifyAge(age) == DataFreshness.stale;
    return '${_relativeTime(age)}${stale ? ' (stale)' : ''}';
  }

  static String _stateLabel(CapabilityAvailability availability) =>
      switch (availability) {
        CapabilityAvailability.available => 'Unknown',
        CapabilityAvailability.unavailable => 'Unavailable',
        CapabilityAvailability.unknown => 'Unknown',
        CapabilityAvailability.unsupported => 'Unsupported',
        CapabilityAvailability.permissionDenied => 'Permission required',
        CapabilityAvailability.serviceDisabled => 'Service off',
        CapabilityAvailability.error => 'Temporarily unavailable',
        CapabilityAvailability.stale => 'Stale',
      };

  static String _relativeTime(Duration age) {
    if (age.isNegative || age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}
