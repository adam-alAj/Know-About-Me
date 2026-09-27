import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/freshness/data_freshness.dart';
import '../../domain/models/activity_state.dart';
import '../../domain/models/device_availability_evidence.dart';
import '../../domain/models/state_observation.dart';
import '../providers/device_state_providers.dart';

/// Minimal developer/debug rendering of Phase 9 activity and availability
/// state (SRS FR-016, FR-017, FR-015).
///
/// Every line is a raw technical observation. Stale, unknown and unsupported
/// states are spelled out rather than hidden, and no line interprets human
/// behaviour — this is intentionally not a partner-facing interpretation UI.
class ActivitySummaryCard extends ConsumerWidget {
  const ActivitySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).nowUtc();
    final activityAsync = ref.watch(currentLocalActivityStateProvider);
    final availability = ref.watch(
      monitoredDeviceStateProvider,
    ).value?.availability;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Activity and availability (technical observations)'),
        const SizedBox(height: AppSpacing.xs),
        activityAsync.when(
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Screen state: ${_screenLabel(state.screenState)}'),
              Text('Activity status: ${_statusLabel(state.activityStatus)}'),
              Text(
                'Last observed activity: '
                '${_lastActivityLabel(state.lastObservedActivityAt, now)}',
              ),
              Text('App lifecycle: ${_lifecycleLabel(state.appLifecycle)}'),
              Text('Observed at: ${_observedLabel(state, now)}'),
              Text('Freshness: ${_freshnessLabel(state.freshnessAt(now))}'),
              Text(
                state.screenState.availability ==
                        CapabilityAvailability.unsupported
                    ? 'Screen capability: unsupported on this platform'
                    : 'Screen capability: supported by this platform',
              ),
              Text(
                'Device availability: ${_availabilityLabel(availability, now)}',
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Technical device observations only; they do not describe '
                'the person behind the phone.',
              ),
            ],
          ),
          loading: () => const Text('Reading activity state...'),
          error: (_, _) => const Text('Activity state temporarily unavailable.'),
        ),
      ],
    );
  }

  static String _screenLabel(StateObservation<DeviceScreenState> observation) {
    final value = observation.value;
    if (observation.availability == CapabilityAvailability.available &&
        value != null) {
      return switch (value) {
        DeviceScreenState.on => 'ON',
        DeviceScreenState.off => 'OFF',
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
        ActivityStatus.activityDetected => 'Activity detected',
        ActivityStatus.noActivityObserved => 'No activity observed',
        ActivityStatus.unknown => 'Unknown',
      };
    }
    return _stateLabel(observation.availability);
  }

  static String _lifecycleLabel(
    StateObservation<AppLifecyclePhase> observation,
  ) {
    final value = observation.value;
    if (observation.availability == CapabilityAvailability.available &&
        value != null) {
      return switch (value) {
        AppLifecyclePhase.foreground => 'FOREGROUND',
        AppLifecyclePhase.background => 'BACKGROUND',
        AppLifecyclePhase.inactive => 'INACTIVE',
        AppLifecyclePhase.hidden => 'HIDDEN',
        AppLifecyclePhase.detached => 'DETACHED',
        AppLifecyclePhase.unknown => 'UNKNOWN',
      };
    }
    return _stateLabel(observation.availability);
  }

  static String _lastActivityLabel(DateTime? timestamp, DateTime now) {
    if (timestamp == null) return 'None observed yet';
    final age = now.toUtc().difference(timestamp.toUtc());
    final stale = age > FreshnessPolicy.standard.recentFor;
    return '${_relativeTime(age)}${stale ? ' (stale)' : ''}';
  }

  static String _observedLabel(ActivityState state, DateTime now) {
    final observedAt =
        state.screenState.observedAt ?? state.appLifecycle.observedAt;
    if (observedAt == null) return 'Unknown';
    return _relativeTime(now.toUtc().difference(observedAt.toUtc()));
  }

  static String _freshnessLabel(DataFreshness freshness) => switch (freshness) {
    DataFreshness.fresh => 'Fresh',
    DataFreshness.recent => 'Recent',
    DataFreshness.stale => 'Stale',
    DataFreshness.unknown => 'Unknown',
  };

  static String _availabilityLabel(
    DeviceAvailabilityEvidence? evidence,
    DateTime now,
  ) {
    if (evidence == null) return 'Unknown';
    final confirmed = evidence.lastConfirmedAvailableAt;
    return switch (evidence.availability) {
      CapabilityAvailability.available => 'AVAILABLE',
      CapabilityAvailability.stale =>
        'STALE${confirmed == null ? '' : ' (last confirmed ${_relativeTime(now.toUtc().difference(confirmed.toUtc()))})'}',
      CapabilityAvailability.unsupported => 'UNSUPPORTED',
      CapabilityAvailability.permissionDenied => 'PERMISSION NOT GRANTED',
      CapabilityAvailability.serviceDisabled => 'SERVICE DISABLED',
      CapabilityAvailability.error => 'ERROR',
      CapabilityAvailability.unavailable => 'UNAVAILABLE',
      CapabilityAvailability.unknown => 'UNKNOWN',
    };
  }

  static String _stateLabel(CapabilityAvailability availability) =>
      switch (availability) {
        CapabilityAvailability.available => 'Unknown',
        CapabilityAvailability.unavailable => 'Unavailable',
        CapabilityAvailability.unknown => 'Unknown',
        CapabilityAvailability.unsupported => 'Unsupported',
        CapabilityAvailability.permissionDenied => 'Permission not granted',
        CapabilityAvailability.serviceDisabled => 'Service disabled',
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
