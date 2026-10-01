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
import '../../../core/ui/widgets/freshness_indicator.dart';
import '../../../core/ui/widgets/section_card.dart';
import '../../../core/ui/widgets/section_header.dart';
import '../../../core/ui/widgets/skeleton.dart';
import '../../../core/ui/widgets/status_pill.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../device_state/domain/models/battery_state.dart';
import '../../device_state/domain/models/network_state.dart';
import '../../device_state/domain/models/pair_sharing_state.dart';
import '../../device_state/domain/models/remote_device_state.dart';
import '../../device_state/domain/models/state_observation.dart';
import '../../device_state/presentation/providers/connection_providers.dart';
import '../../device_state/presentation/providers/device_state_providers.dart';
import '../../device_state/presentation/providers/sync_providers.dart';
import '../../device_state/presentation/widgets/activity_summary_card.dart';
import '../../device_state/presentation/widgets/location_summary_card.dart';
import '../../device_state/presentation/widgets/partner_location_actions.dart';
import '../../history/presentation/recent_history_preview.dart';
import '../../pairing/domain/models/pair_membership.dart';
import '../../pairing/presentation/providers/pairing_providers.dart';
import '../../privacy/domain/models/sharing_category.dart';
import '../../rules/presentation/widgets/rule_interpretations_section.dart';

/// Partner-first dashboard over the authorized Phase 11 state stream.
///
/// Structure answers, in order: who is being viewed, whether their device is
/// currently reachable, when the data was last updated, the shared state itself,
/// and what the user can do next. It contains no Firestore reads and never
/// infers human behaviour.
///
/// Realtime behaviour: the previous value is kept on screen while a refresh is in
/// flight, so a change updates the affected values in place rather than flashing
/// the whole screen back to a loader (Phase 20 §21).
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
    // Ages ("Updated 4 min ago") must keep counting without a data change, so a
    // single minute tick re-renders. It never reads or writes remote state.
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
          final localSnapshot = await ref
              .read(deviceMonitoringControllerProvider)
              .collectNow();
          ref.read(connectionStatusProvider.notifier).refresh();
          await ref
              .read(deviceStateSyncCoordinatorProvider)
              ?.reconcileNow(localSnapshot);
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
              const _PartnerSkeleton()
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
              ),
              const SizedBox(height: AppSpacing.lg),
              if (partnerSharing.isLoading && !partnerState.hasValue)
                const _PartnerSkeleton()
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
              // Interpretations and history are derived from the same authorized
              // partner state, so they only exist while a pair is active. With
              // no connection there is nothing to interpret and nothing shared
              // to recall.
              const SizedBox(height: AppSpacing.xl),
              RuleInterpretationsSection(now: now),
              const SizedBox(height: AppSpacing.lg),
              const RecentHistoryPreview(),
            ],
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(
              title: 'This device',
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
                'Your account exists, but no profile was saved for it. Add a '
                'display name so the person you connect with knows who you are.',
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

/// Who is being viewed, and how current their shared state is.
///
/// Deliberately two things only: a plain reachability statement and the age of
/// the data. Nothing about synchronization internals reaches the user here.
class _PartnerHeader extends StatelessWidget {
  const _PartnerHeader({
    required this.name,
    required this.state,
    required this.now,
  });

  final String name;
  final RemoteDeviceState? state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reach = _reachability(state);
    final observedAt = state?.observedAt;
    final freshness = state?.observationFreshnessAt(now) ?? DataFreshness.unknown;
    final age = observedAt == null ? null : now.toUtc().difference(observedAt);

    return AppCard(
      semanticLabel: '$name, partner',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            child: Text(name.isEmpty ? '?' : name.characters.first),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(
                      label: reach.label,
                      icon: reach.icon,
                      tone: reach.tone,
                    ),
                    if (state != null)
                      FreshnessIndicator(
                        freshness: freshness,
                        age: age,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A reachability statement for the partner's device, in the user's words.
///
/// "Offline" here means *no recent shared update*, never a claim that their
/// phone is off (Phase 20 §8): the pill says "Last known", not "Offline", so the
/// wording cannot be read as a statement about the person.
({String label, IconData icon, StatusTone tone}) _reachability(
  RemoteDeviceState? state,
) {
  if (state == null) {
    return (
      label: 'No update yet',
      icon: Icons.help_outline,
      tone: StatusTone.neutral,
    );
  }
  final observation = state.observation(DeviceMetric.deviceAvailability);
  final value = observation.value;
  if (observation.availability == CapabilityAvailability.available &&
      value is String) {
    return switch (value) {
      'available' => (
        label: 'Online',
        icon: Icons.check_circle_outline,
        tone: StatusTone.positive,
      ),
      'stale' => (
        label: 'Last known',
        icon: Icons.history_toggle_off,
        tone: StatusTone.attention,
      ),
      'unknown' => (
        label: 'Unknown',
        icon: Icons.help_outline,
        tone: StatusTone.neutral,
      ),
      final other => (
        label: _enumLabel(other),
        icon: Icons.help_outline,
        tone: StatusTone.neutral,
      ),
    };
  }
  return switch (observation.availability) {
    CapabilityAvailability.permissionDenied => (
      label: 'Permission required',
      icon: Icons.lock_outline,
      tone: StatusTone.critical,
    ),
    CapabilityAvailability.error => (
      label: 'Unavailable',
      icon: Icons.error_outline,
      tone: StatusTone.attention,
    ),
    CapabilityAvailability.unavailable => (
      label: 'Not shared',
      icon: Icons.visibility_off_outlined,
      tone: StatusTone.neutral,
    ),
    CapabilityAvailability.unsupported => (
      label: 'Unsupported',
      icon: Icons.block_outlined,
      tone: StatusTone.neutral,
    ),
    _ => (label: 'Unknown', icon: Icons.help_outline, tone: StatusTone.neutral),
  };
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
          const AppInlineMessage(
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

    // A refresh keeps the previous value on screen. Riverpod marks the provider
    // as loading again while keeping `hasValue`, and letting that fall through to
    // a loader is what made the dashboard flash on every change.
    if (!stateAsync.hasValue) {
      if (stateAsync.hasError) return _ErrorPanel(onRetry: onRetry);
      return const _PartnerSkeleton();
    }

    final partner = stateAsync.value;
    if (partner == null) {
      return const AppInlineMessage(
        title: 'No shared update yet',
        message: 'There is no shared device state available at this time.',
        tone: AppMessageTone.info,
      );
    }

    return _PartnerSections(state: partner.state, sharing: sharing, now: now);
  }
}

/// The partner's shared state, grouped into a few meaningful sections.
class _PartnerSections extends StatelessWidget {
  const _PartnerSections({
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

    final charge = state.observation(DeviceMetric.chargingState);
    final charging = charge.value == 'charging';
    final duration = state.observation(DeviceMetric.chargingDuration);
    final location = canShowLocation ? state.location : null;

    final sections = <Widget>[
      if (canShowBattery || canShowCharging)
        SectionCard(
          title: 'Battery',
          icon: Icons.battery_charging_full_outlined,
          rows: [
            if (canShowBattery)
              StateRow(
                label: 'Charge',
                value: _metric(
                  state,
                  DeviceMetric.batteryPercentage,
                  now,
                  suffix: '%',
                ),
                emphasis: StateRowEmphasis.strong,
              ),
            if (canShowCharging)
              StateRow(
                label: 'Charging',
                value: _chargingLabel(charge),
              ),
            if (canShowCharging && charging)
              StateRow(
                label: 'Charging duration',
                value: _durationLabel(duration),
              ),
          ],
        ),
      if (canShowNetwork)
        SectionCard(
          title: 'Connection',
          icon: Icons.wifi_outlined,
          rows: [
            StateRow(
              label: 'Connectivity',
              value: _metric(state, DeviceMetric.networkStatus, now),
              emphasis: StateRowEmphasis.strong,
            ),
            StateRow(
              label: 'Last online',
              value: state.lastOnlineAt == null
                  ? 'Unknown'
                  : _relative(state.lastOnlineAt!, now),
            ),
          ],
        ),
      if (canShowActivity)
        SectionCard(
          title: 'Screen and activity',
          icon: Icons.phone_android_outlined,
          rows: [
            StateRow(
              label: 'Screen',
              value: _metric(state, DeviceMetric.screenState, now),
              emphasis: StateRowEmphasis.strong,
            ),
            StateRow(
              label: 'Activity',
              value: _metric(state, DeviceMetric.activityState, now),
            ),
            StateRow(
              label: 'Last activity',
              value: state.lastActivityAt == null
                  ? 'Unknown'
                  : _relative(state.lastActivityAt!, now),
            ),
          ],
        ),
      if (canShowLocation || canShowHome)
        _locationSection(location, canShowLocation, canShowHome, now),
      SectionCard(
        title: 'Sharing',
        icon: Icons.shield_outlined,
        subtitle: 'What your partner has chosen to share with you',
        rows: [
          StateRow(
            label: 'Status',
            value: sharing.paused ? 'Paused' : 'Active',
          ),
          StateRow(
            label: 'Categories',
            value: sharing.categories
                .where(
                  (category) =>
                      category != SharingCategory.ruleInterpretations,
                )
                .map(_categoryLabel)
                .join(', '),
          ),
        ],
        footer: AppButton.secondary(
          label: 'Manage connection and sharing',
          onPressed: () => context.goNamed(AppRoutes.privacy),
        ),
      ),
    ];

    return Column(
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          sections[index],
        ],
      ],
    );
  }

  Widget _locationSection(
    RemoteLocationState? location,
    bool canShowLocation,
    bool canShowHome,
    DateTime now,
  ) {
    final rows = <StateRow>[];
    if (!canShowLocation) {
      rows.add(const StateRow(label: 'Location', value: 'Not shared'));
    } else if (location == null || !location.hasCoordinates) {
      rows.add(
        StateRow(
          label: 'Location',
          value: location == null
              ? 'Unavailable'
              : _availabilityLabel(
                  StateObservation<Object?>(
                    availability: location.availability,
                  ),
                ),
          emphasis: StateRowEmphasis.strong,
        ),
      );
    } else {
      final freshness = location.freshnessAt(now);
      rows.add(
        StateRow(
          label: freshness == DataFreshness.stale
              ? 'Last known location'
              : 'Location',
          value: freshness == DataFreshness.unknown
              ? 'Update time unknown'
              : 'Updated ${_relative(location.observedAt, now)}',
          emphasis: StateRowEmphasis.strong,
        ),
      );
      if (location.approximate) {
        rows.add(const StateRow(label: 'Precision', value: 'Approximate'));
      }
      if (location.accuracyMeters != null) {
        rows.add(
          StateRow(
            label: 'Accuracy',
            value: '±${location.accuracyMeters!.round()} m',
          ),
        );
      }
    }
    if (canShowHome) {
      final distance = location?.distanceFromHomeKm;
      if (distance != null && location?.hasCoordinates == true) {
        rows.add(
          StateRow(
            label: location!.freshnessAt(now) == DataFreshness.stale
                ? 'Last known distance'
                : 'Distance from home',
            value: '${(distance * 1000).round()} m',
          ),
        );
      }
      final presence = location?.freshnessAt(now) == DataFreshness.stale
          ? 'stale'
          : location?.presence?.name;
      rows.add(
        StateRow(
          label: 'At home',
          value: switch (presence) {
            'atHome' => 'At home',
            'nearHome' => 'Near home',
            'awayFromHome' => 'Away',
            'stale' => 'Last known status is stale',
            'unsupported' => 'Unsupported',
            _ => 'Unknown',
          },
          emphasis: StateRowEmphasis.strong,
        ),
      );
    }
    return SectionCard(
      title: 'Location and home',
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

/// The local monitoring surface: what this app can observe on this phone.
///
/// Kept below the partner content because the screen exists to answer questions
/// about the partner; this section is reference material about the user's own
/// device and never competes with the partner state for attention.
class _LocalDeviceOverview extends ConsumerWidget {
  const _LocalDeviceOverview({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(currentLocalBatteryStateProvider);
    final network = ref.watch(currentLocalNetworkStateProvider);
    return Column(
      children: [
        if (battery.hasValue)
          _LocalBatterySummary(state: battery.requireValue, now: now)
        else if (battery.hasError)
          const _UnavailableSection(
            title: 'Battery',
            icon: Icons.battery_charging_full_outlined,
          )
        else
          const SectionSkeleton(
            title: 'Battery',
            icon: Icons.battery_charging_full_outlined,
            rows: 2,
          ),
        const SizedBox(height: AppSpacing.md),
        if (network.hasValue)
          _LocalNetworkSummary(state: network.requireValue, now: now)
        else if (network.hasError)
          const _UnavailableSection(title: 'Network', icon: Icons.wifi_outlined)
        else
          const SectionSkeleton(
            title: 'Network',
            icon: Icons.wifi_outlined,
            rows: 3,
          ),
        const SizedBox(height: AppSpacing.md),
        // These cards bring their own section container, so they are not
        // wrapped again.
        const ActivitySummaryCard(),
        const SizedBox(height: AppSpacing.md),
        const LocationSummaryCard(),
      ],
    );
  }
}

/// A local section whose platform read failed. States the failure rather than
/// leaving a placeholder on screen forever.
class _UnavailableSection extends StatelessWidget {
  const _UnavailableSection({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: title,
    icon: icon,
    rows: const [
      StateRow(label: 'Status', value: 'Temporarily unavailable'),
    ],
  );
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
    return SectionCard(
      title: 'Battery',
      icon: Icons.battery_charging_full_outlined,
      rows: [
        StateRow(
          label: 'Charge',
          value: _localObservation(state.percentage, (value) => '$value%'),
          emphasis: StateRowEmphasis.strong,
        ),
        StateRow(label: 'Charging', value: _localObservation(charge, _batteryChargeLabel)),
        if (charging)
          StateRow(
            label: 'Charging duration',
            value: _localObservation(state.chargingDuration, _durationText),
          ),
        StateRow(
          label: 'Updated',
          value: _relative(
            state.percentage.observedAt ?? charge.observedAt,
            now,
          ),
        ),
      ],
    );
  }
}

class _LocalNetworkSummary extends StatelessWidget {
  const _LocalNetworkSummary({required this.state, required this.now});
  final NetworkState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Network',
      icon: Icons.wifi_outlined,
      rows: [
        StateRow(
          label: 'Connection',
          value: _localObservation(state.connectivity, _connectivityText),
          emphasis: StateRowEmphasis.strong,
        ),
        StateRow(
          label: 'Internet access',
          value: _localObservation(state.internet, _internetText),
        ),
        StateRow(
          label: 'Status',
          value: _localObservation(state.status, _networkStatusText),
        ),
        StateRow(
          label: 'Last online',
          value: _relative(state.lastOnlineAt, now),
        ),
      ],
    );
  }
}

/// Initial load placeholder: mirrors the loaded layout so the screen does not
/// jump when the first value arrives, and never covers the whole screen in a
/// spinner for a small state read.
class _PartnerSkeleton extends StatelessWidget {
  const _PartnerSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SectionSkeleton(rows: 2),
      SizedBox(height: AppSpacing.md),
      SectionSkeleton(rows: 3),
    ],
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

// --------------------------------------------------------------- formatting --

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
  final rendered = value is String ? _enumLabel(value) : '$value';
  return '$rendered$suffix${_freshnessNote(observation.freshnessAt(now))}';
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
