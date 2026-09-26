import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
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
        MetricTile<int>(
          label: 'Battery',
          icon: Icons.battery_full,
          value: state.batteryPercentage,
          format: (value) => '$value%',
        ),
        MetricTile<ChargingState>(
          label: 'Charging',
          icon: Icons.bolt,
          value: state.chargingState,
          format: (value) => switch (value) {
            ChargingState.charging => 'Charging',
            ChargingState.notCharging => 'Not charging',
            ChargingState.fullyCharged => 'Fully charged',
            ChargingState.unknown => 'Unknown',
          },
        ),
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
