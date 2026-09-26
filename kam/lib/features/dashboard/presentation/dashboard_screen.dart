import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/freshness/data_freshness.dart';
import '../../../core/ui/data_state_view.dart';
import '../../../core/ui/presentation_mapping.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_inline_message.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/empty_view.dart';
import '../../../core/ui/widgets/section_header.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../device_state/domain/models/device_state.dart';
import '../../device_state/domain/models/battery_state.dart';
import '../../device_state/domain/models/device_state_snapshot.dart';
import '../../device_state/presentation/providers/device_state_providers.dart';
import '../../device_state/presentation/widgets/metric_tile.dart';

/// The reassurance-oriented partner dashboard shell (SRS FR-045, FR-046).
///
/// Phase 2 renders the real structure and state handling but no live partner
/// data exists yet, so metrics resolve to explicit non-available states rather
/// than fabricated values (SRS FR-048, constraint 4).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final deviceStateAsync = ref.watch(currentDeviceStateProvider);
    final batteryStateAsync = ref.watch(currentLocalBatteryStateProvider);

    // One mapping for every async read. A successful read shows the metrics;
    // each tile then reports its own availability, which is where "Unknown"
    // must appear (FR-048).
    final presentation = PresentationMapping.fromAsyncResult(deviceStateAsync);

    return AppScaffold(
      title: 'Reassurance',
      actions: [
        IconButton(
          tooltip: 'Profile',
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.pushNamed(AppRoutes.profile),
        ),
      ],
      body: ListView(
        children: [
          // An authenticated account whose profile was never stored is reported
          // here as well as on the profile screen, so a partial registration is
          // never silently treated as finished (Phase 4 Task 5, Task 14).
          if (_isProfileMissing(ref)) ...[
            const AppInlineMessage(
              title: 'Finish setting up your profile',
              message:
                  'Your account exists, but no profile was saved for it. Add a '
                  'display name so the person you connect with sees who you are.',
              tone: AppMessageTone.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton.secondary(
              label: 'Go to profile',
              onPressed: () => context.pushNamed(AppRoutes.profile),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const SectionHeader(
            title: 'Your device',
            subtitle: 'What this app can observe about this phone today',
          ),
          AppCard(
            child: DataStateView(
              presentation: presentation,
              onRetry: () => ref.invalidate(currentDeviceStateProvider),
              loadedBuilder: (context) => _DeviceMetricsList(
                state:
                    deviceStateAsync.value?.valueOrNull ??
                    DeviceState.empty('unregistered-device'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: batteryStateAsync.when(
              data: (state) => _BatterySummary(
                state: state,
                now: ref.watch(clockProvider).nowUtc(),
              ),
              loading: () => const Text('Reading local battery state…'),
              error: (_, _) => const Text('Battery state temporarily unavailable.'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Connected partner'),
          AppButton.secondary(
            label: 'Manage pairing and consent',
            onPressed: () => context.pushNamed(AppRoutes.pairing),
          ),
          const SizedBox(height: AppSpacing.sm),
          const AppCard(
            child: SizedBox(
              height: 200,
              child: EmptyView(
                icon: Icons.link_off,
                message:
                    'No partner device data is available yet.',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Environment: ${config.environment.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BatterySummary extends StatelessWidget {
  const _BatterySummary({required this.state, required this.now});

  final BatteryState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final percentage = state.percentage;
    final charging = state.chargingState;
    final duration = state.chargingDuration;
    final isCharging = charging.value == BatteryChargingState.charging ||
        charging.value == BatteryChargingState.full;
    final observedAt = percentage.observedAt ?? charging.observedAt;
    final age = observedAt == null ? null : now.difference(observedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Battery & charging'),
        const SizedBox(height: AppSpacing.xs),
        Text('Battery: ${_observationLabel(percentage, (value) => '$value%')}'),
        Text('Charging: ${_observationLabel(charging, _chargingLabel)}'),
        if (isCharging)
          Text('Charging duration: ${_observationLabel(duration, _durationLabel)}'),
        const SizedBox(height: AppSpacing.xs),
        Text(_freshnessLabel(state, now, age)),
      ],
    );
  }

  static String _observationLabel<T>(
    StateObservation<T> observation,
    String Function(T value) format,
  ) {
    final value = observation.value;
    if (observation.availability == CapabilityAvailability.available &&
        value != null) {
      return format(value);
    }
    return switch (observation.availability) {
      CapabilityAvailability.unsupported => 'Unsupported',
      CapabilityAvailability.permissionDenied => 'Permission not granted',
      CapabilityAvailability.error => 'Temporarily unavailable',
      CapabilityAvailability.stale => 'Stale',
      CapabilityAvailability.unknown => 'Unknown',
      CapabilityAvailability.unavailable => 'Unavailable',
      CapabilityAvailability.available => 'Unknown',
    };
  }

  static String _chargingLabel(BatteryChargingState value) => switch (value) {
    BatteryChargingState.charging => 'Charging',
    BatteryChargingState.full => 'Full',
    BatteryChargingState.discharging => 'Discharging',
    BatteryChargingState.notCharging => 'Not charging',
    BatteryChargingState.unknown => 'Unknown',
  };

  static String _durationLabel(Duration value) {
    final minutes = value.inMinutes;
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0 && remainder == 0) return 'Less than a minute';
    if (hours == 0) return '${remainder}m';
    return '${hours}h ${remainder}m';
  }

  static String _freshnessLabel(BatteryState state, DateTime now, Duration? age) {
    if (state.freshnessAt(now) == DataFreshness.stale) {
      return age == null ? 'Battery data is stale.' : 'Last updated ${age.inMinutes}m ago.';
    }
    if (age == null) return 'Battery update time unknown.';
    return age.inSeconds < 60 ? 'Updated just now.' : 'Updated ${age.inMinutes}m ago.';
  }
}

/// Whether the signed-in user has no profile document.
///
/// Only a *resolved* read that returned `null` counts: a load in progress or a
/// failed read must not be presented as "your profile is missing" (FR-048).
bool _isProfileMissing(WidgetRef ref) {
  final identity = ref.watch(currentIdentityProvider);
  if (identity == null) return false;
  final profile = ref.watch(currentUserProfileProvider);
  if (!profile.hasValue) return false;
  return profile.requireValue.valueOrNull == null;
}

/// Renders the observable device metrics.
///
/// Each [MetricTile] shows the value, or an explicit Unknown/Unsupported state
/// with its freshness, so the screen never implies data it does not have.
class _DeviceMetricsList extends StatelessWidget {
  const _DeviceMetricsList({required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MetricTile<NetworkStatus>(
          label: 'Network',
          icon: Icons.wifi,
          value: state.networkStatus,
          format: (value) => switch (value) {
            NetworkStatus.online => 'Online',
            NetworkStatus.offline => 'Offline',
            NetworkStatus.wifi => 'Wi-Fi',
            NetworkStatus.mobile => 'Mobile data',
            NetworkStatus.unknown => 'Unknown',
          },
        ),
        MetricTile<DeviceAvailabilityState>(
          label: 'Availability',
          icon: Icons.sensors,
          value: state.availability,
          format: (value) => switch (value) {
            DeviceAvailabilityState.active => 'Active',
            DeviceAvailabilityState.recentlySeen => 'Recently seen',
            DeviceAvailabilityState.offline => 'Offline',
            DeviceAvailabilityState.unknown => 'Unknown',
          },
        ),
      ],
    );
  }
}
