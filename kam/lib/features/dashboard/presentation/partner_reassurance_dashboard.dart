import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/domain/device_metric.dart';
import '../../../core/freshness/data_freshness.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_inline_message.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/section_header.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../device_state/domain/models/battery_state.dart';
import '../../device_state/domain/models/network_state.dart';
import '../../device_state/domain/models/pair_sharing_state.dart';
import '../../device_state/domain/models/remote_device_state.dart';
import '../../device_state/domain/models/state_observation.dart';
import '../../device_state/presentation/providers/connection_providers.dart';
import '../../device_state/presentation/providers/sync_providers.dart';
import '../../device_state/presentation/providers/device_state_providers.dart';
import '../../device_state/presentation/widgets/activity_summary_card.dart';
import '../../device_state/presentation/widgets/location_summary_card.dart';
import '../../device_state/presentation/widgets/partner_location_actions.dart';
import '../../history/presentation/recent_history_preview.dart';
import '../../pairing/domain/models/pair_membership.dart';
import '../../pairing/presentation/providers/pairing_providers.dart';
import '../../privacy/domain/models/sharing_category.dart';
import '../../rules/presentation/widgets/rule_interpretations_section.dart';

/// Partner-first dashboard over the authorized Phase 11 state stream.
/// It contains no Firestore reads and never infers human behavior.
class PartnerReassuranceDashboard extends ConsumerStatefulWidget {
  const PartnerReassuranceDashboard({super.key});

  @override
  ConsumerState<PartnerReassuranceDashboard> createState() =>
      _PartnerReassuranceDashboardState();
}

class _PartnerReassuranceDashboardState
    extends ConsumerState<PartnerReassuranceDashboard> {
  Timer? _displayTimer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = ref.read(clockProvider).nowUtc();
    _displayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = ref.read(clockProvider).nowUtc());
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final memberships = ref.watch(pairMembershipsProvider);
    final scopeAsync = ref.watch(partnerScopeProvider);
    final scope = scopeAsync.value;
    final now = _now;
    final titleName = ref.watch(partnerDisplayNameProvider).value;
    final partnerState = ref.watch(authorizedPartnerDeviceStateProvider);
    final partnerSharing = ref.watch(partnerSharingProvider);

    final membership = _membershipFor(memberships.value, scope);
    final hasActiveScope = scope != null && membership?.isActive == true;

    return AppScaffold(
      title: 'Reassurance',
      actions: [
        IconButton(
          tooltip: 'Profile',
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.pushNamed(AppRoutes.profile),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          // A manual refresh re-reads the actual sources; a widget rebuild is
          // not a data refresh (Phase 20 §21).
          //   1. Re-collect this device's own capabilities from the platform.
          //   2. Re-derive the connection from the latest evidence.
          //   3. Give an unfinished publish another (coalesced) trigger.
          //   4. Re-subscribe the authorized partner streams. Invalidating a
          //      provider cancels its old listener and creates exactly one new
          //      one, so no duplicate Firestore listener is left behind.
          await ref.read(deviceMonitoringControllerProvider).collectNow();
          ref.read(connectionStatusProvider.notifier).refresh();
          ref.read(deviceStateSyncCoordinatorProvider)?.reassertLatest();
          ref.invalidate(partnerSharingProvider);
          ref.invalidate(partnerDeviceStateProvider);
          ref.invalidate(partnerDisplayNameProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const _IncompleteProfileNotice(),
            if (memberships.isLoading || scopeAsync.isLoading)
              const _LoadingPanel()
            else if (memberships.hasError || scopeAsync.hasError)
              _ErrorPanel(
                onRetry: () => ref.invalidate(pairMembershipsProvider),
              )
            else if (!hasActiveScope)
              _ConnectionEmptyState(memberships: memberships.value ?? const [])
            else ...[
              _PartnerHeader(
                name: titleName ?? 'Your partner',
                state: partnerState.value?.state,
                now: now,
                isFromCache: partnerState.value?.state.isFromCache ?? false,
                connectionFromCache: membership?.isFromCache ?? false,
              ),
              const SizedBox(height: AppSpacing.md),
              if (partnerSharing.isLoading)
                const AppCard(
                  child: Text('Checking your partner’s sharing settings…'),
                )
              else if (partnerSharing.hasError)
                const AppInlineMessage(
                  title: 'Sharing status unavailable',
                  message:
                      'Partner details are hidden until their sharing settings can be confirmed.',
                  tone: AppMessageTone.warning,
                )
              else
                _PartnerContent(
                  stateAsync: partnerState,
                  sharing: partnerSharing.value ?? PairSharingState.none,
                  now: now,
                  onRetry: () => ref.invalidate(partnerDeviceStateProvider),
                ),
              const SizedBox(height: AppSpacing.lg),
              // Rule interpretations are derived from the same authorized state
              // the panels above display, so they live here rather than in a
              // separate screen: the facts and the user's reading of them stay
              // side by side.
              RuleInterpretationsSection(now: now),
              const SizedBox(height: AppSpacing.lg),
              const RecentHistoryPreview(),
              const SizedBox(height: AppSpacing.lg),
              // Sharing categories and connection controls (pause, disconnect,
              // revoke) both live on the Privacy tab; Pairing only issues and
              // redeems codes, so it is not where sharing is managed.
              AppButton.secondary(
                label: 'Manage connection and sharing',
                onPressed: () => context.goNamed(AppRoutes.privacy),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'Your device',
              subtitle: 'What this app can observe on this phone',
            ),
            _LocalDeviceOverview(now: now),
          ],
        ),
      ),
    );
  }

  static PairMembership? _membershipFor(
    List<PairMembership>? memberships,
    Object? scope,
  ) {
    if (memberships == null || scope is! PartnerScope) return null;
    for (final membership in memberships) {
      if (membership.pairId == scope.pairId) return membership;
    }
    return null;
  }
}

class _IncompleteProfileNotice extends ConsumerWidget {
  const _IncompleteProfileNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider);
    if (identity == null) return const SizedBox.shrink();
    final profile = ref.watch(currentUserProfileProvider);
    if (!profile.hasValue ||
        profile.requireValue.isFailure ||
        profile.requireValue.valueOrNull != null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppInlineMessage(
            title: 'Finish setting up your profile',
            message:
                'Your account exists, but no profile was saved for it. Add a display name so the person you connect with sees who you are.',
            tone: AppMessageTone.warning,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(
            label: 'Go to profile',
            onPressed: () => context.pushNamed(AppRoutes.profile),
          ),
        ],
      ),
    );
  }
}

/// Retains the existing local monitoring surface alongside the new partner
/// dashboard; all fields remain explicit when unknown or unsupported.
class _LocalDeviceOverview extends ConsumerWidget {
  const _LocalDeviceOverview({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(currentLocalBatteryStateProvider);
    final network = ref.watch(currentLocalNetworkStateProvider);
    return Column(
      children: [
        AppCard(
          child: battery.when(
            data: (state) => _LocalBatterySummary(state: state, now: now),
            loading: () => const Text('Reading local battery state…'),
            error: (_, _) =>
                const Text('Battery state temporarily unavailable.'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),        AppCard(child: network.when(
            data: (state) => _LocalNetworkSummary(state: state, now: now),
            loading: () => const Text('Reading local network state…'),
            error: (_, _) =>
                const Text('Network state temporarily unavailable.'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppCard(child: ActivitySummaryCard()),
        const SizedBox(height: AppSpacing.sm),
        const AppCard(child: LocationSummaryCard()),
      ],
    );
  }
}

class _LocalBatterySummary extends StatelessWidget {
  const _LocalBatterySummary({required this.state, required this.now});
  final BatteryState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final charge = state.chargingState;
    final charging =
        charge.value == BatteryChargingState.charging ||
        charge.value == BatteryChargingState.full;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Battery & charging',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Battery: ${_localObservation(state.percentage, (value) => '$value%')}',
        ),
        Text('Charging: ${_localObservation(charge, _batteryChargeLabel)}'),
        if (charging)
          Text(
            'Charging duration: ${_localObservation(state.chargingDuration, _durationText)}',
          ),
        Text(
          'Updated: ${_relative(state.percentage.observedAt ?? charge.observedAt, now)}',
        ),
        Text('Freshness: ${_freshnessLabel(state.freshnessAt(now))}'),
      ],
    );
  }
}

class _LocalNetworkSummary extends StatelessWidget {
  const _LocalNetworkSummary({required this.state, required this.now});
  final NetworkState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Network', style: Theme.of(context).textTheme.titleMedium),
      Text(
        'Connection: ${_localObservation(state.connectivity, _connectivityText)}',
      ),
      Text(
        'Internet access: ${_localObservation(state.internet, _internetText)}',
      ),
      Text('Status: ${_localObservation(state.status, _networkStatusText)}'),
      Text('Last online: ${_relative(state.lastOnlineAt, now)}'),
      Text('Freshness: ${_freshnessLabel(state.freshnessAt(now))}'),
    ],
  );
}

class _PartnerHeader extends StatelessWidget {
  const _PartnerHeader({
    required this.name,
    required this.state,
    required this.now,
    required this.isFromCache,
    required this.connectionFromCache,
  });

  final String name;
  final RemoteDeviceState? state;
  final DateTime now;
  final bool isFromCache;
  final bool connectionFromCache;

  @override
  Widget build(BuildContext context) {
    final freshness =
        state?.observationFreshnessAt(now) ?? DataFreshness.unknown;
    final observedAt = state?.observedAt;
    return AppCard(
      semanticLabel: '$name, connected partner',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Text(name.isEmpty ? '?' : name.characters.first),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      connectionFromCache
                          ? 'Last known connection · checking status'
                          : 'Connected',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.link, semanticLabel: 'Connection active'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            observedAt == null
                ? 'Partner device update time unknown'
                : 'Last observed ${_relative(observedAt, now)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text('Device state: ${_freshnessLabel(freshness)}'),
          if (isFromCache)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Showing cached data.'),
            ),
          if (connectionFromCache && !isFromCache)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Connection status is cached.'),
            ),
        ],
      ),
    );
  }
}

class _PartnerContent extends StatelessWidget {
  const _PartnerContent({
    required this.stateAsync,
    required this.sharing,
    required this.now,
    required this.onRetry,
  });

  final AsyncValue<PartnerDeviceState?> stateAsync;
  final PairSharingState sharing;
  final DateTime now;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!sharing.sharesAnything) {
      // A new connection shares nothing until *each* member turns categories on
      // for themselves, so this state is usually "the partner has not opted in
      // yet", not a fault. Say where to do it instead of leaving the user to
      // guess that the connection is broken.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInlineMessage(
            title: 'Nothing is shared yet',
            message:
                'Your partner has not shared anything yet. They choose what to '
                'share under Privacy.',
            tone: AppMessageTone.info,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(
            label: 'Choose what I share',
            onPressed: () => context.goNamed(AppRoutes.privacy),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (sharing.isFromCache)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppInlineMessage(
              title: 'Sharing status is cached',
              message:
                  'These are the last known settings. Access may have changed while offline.',
              tone: AppMessageTone.info,
            ),
          ),
        stateAsync.when(
          loading: () => const _LoadingPanel(),
          error: (_, _) => _ErrorPanel(onRetry: onRetry),
          data: (partner) {
            if (partner == null) {
              return const AppInlineMessage(
                title: 'No device update yet',
                message:
                    'There is no shared device state available at this time.',
                tone: AppMessageTone.info,
              );
            }
            return _PartnerMetrics(
              state: partner.state,
              sharing: sharing,
              now: now,
            );
          },
        ),
      ],
    );
  }
}

class _PartnerMetrics extends StatelessWidget {
  const _PartnerMetrics({
    required this.state,
    required this.sharing,
    required this.now,
  });

  final RemoteDeviceState state;
  final PairSharingState sharing;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final canShowBattery = sharing.shares(SharingCategory.battery);

    final canShowCharging = sharing.shares(SharingCategory.charging);
    final canShowNetwork = sharing.shares(SharingCategory.network);
    final canShowActivity = sharing.shares(SharingCategory.activityIndicators);
    final canShowLocation = sharing.shares(SharingCategory.location);
    final canShowHome = sharing.shares(SharingCategory.distanceFromHome);
    final location = canShowLocation ? state.location : null;
    final charge = state.observation(DeviceMetric.chargingState);
    final charging = charge.value == 'charging';
    final duration = state.observation(DeviceMetric.chargingDuration);

    return Column(
      children: [
        _StateCard(
          title: 'Device availability',
          icon: Icons.devices_outlined,
          rows: [
            _StateRow(
              'Availability',
              _availabilityLabel(
                state.observation(DeviceMetric.deviceAvailability),
              ),
            ),
            _StateRow(
              'Last online',
              state.lastOnlineAt == null
                  ? 'Unknown'
                  : _relative(state.lastOnlineAt!, now),
            ),
          ],
        ),
        if (canShowBattery || canShowCharging) ...[
          const SizedBox(height: AppSpacing.sm),
          _StateCard(
            title: 'Battery & charging',
            icon: Icons.battery_charging_full,
            rows: [
              if (canShowBattery)
                _StateRow(
                  'Battery',
                  _metric(
                    state,
                    DeviceMetric.batteryPercentage,
                    now,
                    suffix: '%',
                  ),
                ),
              if (canShowCharging)
                _StateRow('Charging', _chargingLabel(charge)),
              if (canShowCharging && charging)
                _StateRow('Charging duration', _durationLabel(duration)),
              if (canShowBattery || canShowCharging)
                _StateRow('Updated', _relative(state.observedAt, now)),
            ],
          ),
        ],
        if (canShowNetwork) ...[
          const SizedBox(height: AppSpacing.sm),
          _StateCard(
            title: 'Network',
            icon: Icons.wifi_outlined,
            rows: [
              _StateRow(
                'Connectivity',
                _metric(state, DeviceMetric.networkStatus, now),
              ),
              _StateRow(
                'Last online',
                state.lastOnlineAt == null
                    ? 'Unknown'
                    : _relative(state.lastOnlineAt!, now),
              ),
            ],
          ),
        ],
        if (canShowActivity) ...[
          const SizedBox(height: AppSpacing.sm),
          _StateCard(
            title: 'Activity indicators',
            icon: Icons.phone_android,
            rows: [
              _StateRow(
                'Screen',
                _metric(state, DeviceMetric.screenState, now),
              ),
              _StateRow(
                'Activity state',
                _metric(state, DeviceMetric.activityState, now),
              ),
              _StateRow(
                'Last observable activity',
                state.lastActivityAt == null
                    ? 'Unknown'
                    : _relative(state.lastActivityAt!, now),
              ),
            ],
          ),
        ],
        if (canShowLocation || canShowHome) ...[
          const SizedBox(height: AppSpacing.sm),
          _locationCard(location, canShowLocation, canShowHome, now),
        ],
        const SizedBox(height: AppSpacing.sm),
        _StateCard(
          title: 'Sharing & privacy',
          icon: Icons.shield_outlined,
          rows: [
            _StateRow('Sharing', sharing.paused ? 'Paused' : 'Active'),
            _StateRow(
              'Categories shared',
              sharing.categories
                  .where(
                    (category) =>
                        category != SharingCategory.ruleInterpretations,
                  )
                  .map(_categoryLabel)
                  .join(', '),
            ),
          ],
        ),
      ],
    );
  }

  Widget _locationCard(
    RemoteLocationState? location,
    bool canShowLocation,
    bool canShowHome,
    DateTime now,
  ) {
    final rows = <_StateRow>[];
    if (!canShowLocation) {
      rows.add(const _StateRow('Location', 'Not shared'));
    } else if (location == null || !location.hasCoordinates) {
      rows.add(
        _StateRow(
          'Location',
          location == null
              ? 'Unavailable'
              : _availabilityLabel(
                  StateObservation<Object?>(
                    availability: location.availability,
                  ),
                ),
        ),
      );
    } else {
      final freshness = location.freshnessAt(now);
      rows.add(
        _StateRow(
          freshness == DataFreshness.stale ? 'Last known location' : 'Location',
          freshness == DataFreshness.unknown
              ? 'Update time unknown'
              : 'Updated ${_relative(location.observedAt, now)} · ${_freshnessLabel(freshness)}',
        ),
      );
      if (location.approximate) {
        rows.add(const _StateRow('Precision', 'Approximate'));
      }
      if (location.accuracyMeters != null) {
        rows.add(
          _StateRow(
            'Approximate accuracy',
            '±${location.accuracyMeters!.round()} m',
          ),
        );
      }
    }
    if (canShowHome) {
      final distance = location?.distanceFromHomeKm;
      if (distance != null && location?.hasCoordinates == true) {
        rows.add(
          _StateRow(
            location!.freshnessAt(now) == DataFreshness.stale
                ? 'Last known distance from home'
                : 'Distance from home',
            '${(distance * 1000).round()} m',
          ),
        );
      }
      final presence = location?.freshnessAt(now) == DataFreshness.stale
          ? 'stale'
          : location?.presence?.name;
      rows.add(
        _StateRow('At home / away', switch (presence) {
          'atHome' => 'At home',
          'nearHome' => 'Near home',
          'awayFromHome' => 'Away from home',
          'stale' => 'Last known status is stale',
          'unsupported' => 'Unsupported',
          _ => 'Unknown',
        }),
      );
    }
    return _StateCard(
      title: 'Location & home',
      icon: Icons.location_on_outlined,
      rows: rows,
      // Offered only for a usable coordinate the partner has actually shared;
      // a stale fix is labelled as the last known location, not as current.
      footer: location != null && location.hasCoordinates
          ? PartnerLocationActions(location: location, now: now)
          : null,
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.footer,
  });

  final String title;
  final IconData icon;
  final List<_StateRow> rows;

  /// Optional action rendered under the rows (for example "Open in Google
  /// Maps" for an authorized location).
  final Widget? footer;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, semanticLabel: title),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(row.label)),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(row.value, textAlign: TextAlign.end)),
              ],
            ),
          ),
        ?footer,
      ],
    ),
  );
}

class _StateRow {
  const _StateRow(this.label, this.value);
  final String label;
  final String value;
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();
  @override
  Widget build(BuildContext context) => const AppCard(
    child: Row(
      children: [
        CircularProgressIndicator(),
        SizedBox(width: AppSpacing.md),
        Text('Loading partner state…'),
      ],
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppInlineMessage(
        title: 'Partner state unavailable',
        message: 'The latest partner state could not be loaded. Try again.',
        tone: AppMessageTone.warning,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppButton.secondary(label: 'Retry', onPressed: onRetry),
    ],
  );
}

class _ConnectionEmptyState extends StatelessWidget {
  const _ConnectionEmptyState({required this.memberships});
  final List<PairMembership> memberships;

  @override
  Widget build(BuildContext context) {
    final pending = memberships.any((pair) => pair.isPending);
    final ended = memberships.any((pair) => pair.isEnded);
    final title = pending
        ? 'Connection awaiting consent'
        : ended
        ? 'Connection unavailable'
        : 'No active connection';
    final message = pending
        ? 'Both people must consent before partner device details are available.'
        : ended
        ? 'This connection has ended. Partner device details are no longer shown.'
        : 'Connect with your partner to see the device information they choose to share.';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(message),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: pending ? 'Review connection' : 'Connect with partner',
            onPressed: () => context.goNamed(AppRoutes.pairing),
          ),
        ],
      ),
    );
  }
}

String _metric(
  RemoteDeviceState state,
  DeviceMetric metric,
  DateTime now, {
  String suffix = '',
}) {
  final observation = state.observation(metric);
  final value = observation.value;
  if (observation.availability != CapabilityAvailability.available ||
      value == null) {
    return _availabilityLabel(observation);
  }
  return '${value is String ? _enumLabel(value) : value}$suffix'
      '${_freshnessNote(observation.freshnessAt(now))}';
}

/// Marks a partner value that is no longer current as the last known one.
///
/// The partner's own observation age is the only evidence available: once their
/// state stops advancing, an old value must not read as a live one. It is never
/// turned into an "offline" claim — an absent update is not proof that the
/// partner's device is off or offline (Phase 20 §8).
String _freshnessNote(DataFreshness freshness) => switch (freshness) {
  DataFreshness.recent => ' · last known',
  DataFreshness.stale => ' · stale',
  DataFreshness.fresh || DataFreshness.unknown => '',
};

String _chargingLabel(StateObservation<Object?> observation) {
  if (observation.availability != CapabilityAvailability.available ||
      observation.value == null) {
    return _availabilityLabel(observation);
  }
  return switch (observation.value) {
    'charging' => 'Charging',
    'discharging' => 'Not charging',
    'full' => 'Full',
    'notCharging' => 'Not charging',
    final value => '$value',
  };
}

String _durationLabel(StateObservation<Object?> observation) {
  if (observation.availability != CapabilityAvailability.available ||
      observation.value is! Duration) {
    return _availabilityLabel(observation);
  }
  final duration = observation.value! as Duration;
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

String _availabilityLabel(StateObservation<Object?> observation) {
  if (observation.availability == CapabilityAvailability.available &&
      observation.value != null) {
    return _enumLabel('${observation.value}');
  }
  return switch (observation.availability) {
    CapabilityAvailability.available ||
    CapabilityAvailability.unknown => 'Unknown',
    CapabilityAvailability.unavailable => 'Not shared',
    CapabilityAvailability.unsupported => 'Unsupported',
    CapabilityAvailability.permissionDenied => 'Permission required',
    CapabilityAvailability.serviceDisabled => 'Location off',
    CapabilityAvailability.error => 'Unavailable',
    CapabilityAvailability.stale => 'Stale',
  };
}

String _enumLabel(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .replaceAll('_', ' ')
    .replaceFirstMapped(RegExp(r'^.'), (match) => match[0]!.toUpperCase());

String _freshnessLabel(DataFreshness value) => switch (value) {
  DataFreshness.fresh => 'Fresh',
  DataFreshness.recent => 'Recently updated',
  DataFreshness.stale => 'Stale',
  DataFreshness.unknown => 'Unknown',
};

String _relative(DateTime? timestamp, DateTime now) {
  if (timestamp == null) return 'unknown';
  final age = now.toUtc().difference(timestamp.toUtc());
  if (age.isNegative || age.inSeconds < 60) return 'just now';
  if (age.inMinutes < 60) {
    return '${age.inMinutes} minute${age.inMinutes == 1 ? '' : 's'} ago';
  }
  if (age.inHours < 24) {
    return '${age.inHours} hour${age.inHours == 1 ? '' : 's'} ago';
  }
  final local = timestamp.toLocal();
  if (age.inDays == 1) return 'yesterday at ${_time(local)}';
  return '${age.inDays} days ago at ${_time(local)}';
}

String _time(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

String _categoryLabel(SharingCategory category) => switch (category) {
  SharingCategory.battery => 'Battery',
  SharingCategory.charging => 'Charging',
  SharingCategory.network => 'Network',
  SharingCategory.location => 'Location',
  SharingCategory.distanceFromHome => 'Distance from home',
  SharingCategory.activityIndicators => 'Activity indicators',
  SharingCategory.ruleInterpretations => 'Interpretations',
};

String _localObservation<T>(
  StateObservation<T> observation,
  String Function(T value) format,
) {
  final value = observation.value;
  if (observation.availability == CapabilityAvailability.available) {
    if (value != null) return format(value);
    return 'Unknown';
  }
  return switch (observation.availability) {
    CapabilityAvailability.available ||
    CapabilityAvailability.unknown => 'Unknown',
    CapabilityAvailability.unavailable => 'Unavailable',
    CapabilityAvailability.unsupported => 'Unsupported',
    CapabilityAvailability.permissionDenied => 'Permission required',
    CapabilityAvailability.serviceDisabled => 'Service off',
    CapabilityAvailability.error => 'Temporarily unavailable',
    CapabilityAvailability.stale => 'Stale',
  };
}

String _batteryChargeLabel(BatteryChargingState value) => switch (value) {
  BatteryChargingState.charging => 'Charging',
  BatteryChargingState.full => 'Full',
  BatteryChargingState.discharging => 'Not charging',
  BatteryChargingState.notCharging => 'Not charging',
  BatteryChargingState.unknown => 'Unknown',
};

String _durationText(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes % 60;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

String _connectivityText(ConnectivityType value) => switch (value) {
  ConnectivityType.wifi => 'Wi-Fi',
  ConnectivityType.mobile => 'Mobile',
  ConnectivityType.ethernet => 'Ethernet',
  ConnectivityType.bluetooth => 'Bluetooth',
  ConnectivityType.vpn => 'VPN',
  ConnectivityType.none => 'None',
  ConnectivityType.unknown => 'Unknown',
};

String _internetText(InternetReachability value) => switch (value) {
  InternetReachability.available => 'Available',
  InternetReachability.unavailable => 'Unavailable',
  InternetReachability.unknown => 'Unknown',
};

String _networkStatusText(NetworkOnlineStatus value) => switch (value) {
  NetworkOnlineStatus.online => 'Online',
  NetworkOnlineStatus.offline => 'Offline',
  NetworkOnlineStatus.unknown => 'Unknown',
};
