import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/domain/device_metric.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../pairing/presentation/providers/pairing_providers.dart';
import '../../../privacy/domain/models/sharing_category.dart';
import '../../domain/models/pair_sharing_state.dart';
import '../../domain/models/remote_device_state.dart';
import '../../domain/models/state_observation.dart';
import '../../domain/models/sync_payload.dart';
import '../../domain/services/device_state_sync_service.dart';
import '../providers/sync_providers.dart';

/// Development view of real-time synchronization (Phase 11 §44).
///
/// This is a state-inspection surface, not the partner dashboard: the reassurance
/// dashboard belongs to Phase 12. Its job is to make the synchronization
/// semantics visible and checkable — what is shared, when the partner's value was
/// observed, when it was synchronized, and whether it came from cache.
class PartnerSyncCard extends ConsumerStatefulWidget {
  const PartnerSyncCard({super.key});

  @override
  ConsumerState<PartnerSyncCard> createState() => _PartnerSyncCardState();
}

class _PartnerSyncCardState extends ConsumerState<PartnerSyncCard> {
  bool _busy = false;

  Future<void> _applySharing({
    required String pairId,
    required String userId,
    required bool paused,
    required Set<SharingCategory> categories,
  }) async {
    final repository = ref.read(sharingRepositoryProvider);
    if (repository == null || _busy) return;
    setState(() => _busy = true);
    try {
      await repository.setSharing(
        pairId: pairId,
        userId: userId,
        paused: paused,
        categories: categories,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update sharing. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeAsync = ref.watch(partnerScopeProvider);
    final scope = scopeAsync.value;
    final uid = ref.watch(currentIdentityProvider)?.uid;
    final firebaseReady = ref.watch(deviceStateSyncGatewayProvider) != null;

    if (!firebaseReady) {
      return const Text(
        'Synchronization is unavailable in this build, so nothing leaves this '
        'device.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Real-time synchronization'),
        const SizedBox(height: AppSpacing.xs),
        if (scopeAsync.isLoading)
          const Text('Checking connection…')
        else if (scope == null)
          const Text(
            'No active connection. Your device state stays on this device and '
            'nothing is published.',
          )
        else ...[
          _OwnPublicationStatus(pairId: scope.pairId),
          const Divider(height: AppSpacing.lg),
          _SharingControls(
            pairId: scope.pairId,
            userId: uid,
            busy: _busy,
            onApply: _applySharing,
          ),
          const Divider(height: AppSpacing.lg),
          const _PartnerStateSection(),
        ],
      ],
    );
  }
}

/// What this device is currently publishing.
class _OwnPublicationStatus extends ConsumerWidget {
  const _OwnPublicationStatus({required this.pairId});

  final String pairId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharingAsync = ref.watch(ownSharingProvider);
    final resultsAsync = ref.watch(deviceStateSyncResultsProvider);
    final version = ref.watch(deviceStateSyncServiceProvider)?.currentVersion;
    final sharing = sharingAsync.value ?? PairSharingState.none;
    final outcomes = resultsAsync.value ?? const <SyncOutcome>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sharing.paused
              ? 'Sharing: paused — nothing is published'
              : sharing.sharesAnything
              ? 'Sharing: ${sharing.categoryNames.join(', ')}'
              : 'Sharing: nothing selected yet',
        ),
        if (version != null) Text('State version: $version'),
        if (outcomes.isEmpty)
          const Text('Nothing published yet.')
        else
          for (final outcome in outcomes)
            Text(
              '${_documentLabel(outcome.kind)}: ${_decisionLabel(outcome.decision)}'
              '${outcome.reason == null ? '' : ' (${outcome.reason})'}',
            ),
      ],
    );
  }

  static String _documentLabel(SyncDocumentKind kind) =>
      kind == SyncDocumentKind.location ? 'Location' : 'Device state';

  static String _decisionLabel(SyncDecision decision) => switch (decision) {
    SyncDecision.published => 'published',
    SyncDecision.deleted => 'removed',
    SyncDecision.unchanged => 'unchanged, not written',
    SyncDecision.withheld => 'nothing trustworthy to publish',
    SyncDecision.failed => 'failed, retrying with backoff',
    SyncDecision.blocked => 'refused, will not be retried',
  };
}

/// The user's own sharing switches.
///
/// Location is listed last and separately because it is the most sensitive
/// category and is gated independently of everything else (NFR-036).
class _SharingControls extends ConsumerWidget {
  const _SharingControls({
    required this.pairId,
    required this.userId,
    required this.busy,
    required this.onApply,
  });

  final String pairId;
  final String? userId;
  final bool busy;
  final Future<void> Function({
    required String pairId,
    required String userId,
    required bool paused,
    required Set<SharingCategory> categories,
  })
  onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing =
        ref.watch(ownSharingProvider).value ?? PairSharingState.none;
    final owner = userId;
    final enabled = owner != null && !busy;

    Future<void> apply({bool? paused, Set<SharingCategory>? categories}) =>
        onApply(
          pairId: pairId,
          userId: owner ?? '',
          paused: paused ?? sharing.paused,
          categories: categories ?? sharing.categories,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What you share with your partner'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Pause all sharing'),
          subtitle: const Text(
            'Pausing hides everything immediately without disconnecting.',
          ),
          value: sharing.paused,
          onChanged: enabled ? (value) => apply(paused: value) : null,
        ),
        for (final category in SharingCategory.values)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(_categoryLabel(category)),
            subtitle: category == SharingCategory.location
                ? const Text(
                    'Coordinates are shared only when you enable this '
                    'separately from the OS permission.',
                  )
                : null,
            value: sharing.categories.contains(category),
            onChanged: enabled
                ? (checked) {
                    final next = Set<SharingCategory>.of(sharing.categories);
                    if (checked == true) {
                      next.add(category);
                    } else {
                      next.remove(category);
                    }
                    apply(categories: next);
                  }
                : null,
          ),
      ],
    );
  }

  static String _categoryLabel(SharingCategory category) => switch (category) {
    SharingCategory.battery => 'Battery level',
    SharingCategory.charging => 'Charging',
    SharingCategory.network => 'Network status',
    SharingCategory.location => 'Location',
    SharingCategory.distanceFromHome => 'Distance from home',
    SharingCategory.activityIndicators => 'Activity indicators',
    SharingCategory.ruleInterpretations => 'Interpretations (later phase)',
  };
}

/// The partner's synchronized state, labelled with both clocks.
class _PartnerStateSection extends ConsumerWidget {
  const _PartnerStateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(authorizedPartnerDeviceStateProvider);
    final now = ref.watch(clockProvider).nowUtc();

    return partnerAsync.when(
      loading: () => const Text('Reading partner state…'),
      error: (_, _) => const Text(
        'Partner state is not readable right now. It will resume when the '
        'connection allows.',
      ),
      data: (partner) {
        if (partner == null) {
          return const Text('Your partner has not shared anything yet.');
        }
        final state = partner.state;
        final location = state.location;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Partner device'),
            Text('Availability: ${state.deviceAvailability.name}'),
            Text(
              'Battery: ${_observationSummary(state, DeviceMetric.batteryPercentage, (value) => '$value%')}',
            ),
            Text('Charging: ${_chargingSummary(state)}'),
            Text(
              'Network: ${_observationSummary(state, DeviceMetric.networkStatus, (value) => '$value')}',
            ),
            Text(
              'Screen: ${_observationSummary(state, DeviceMetric.screenState, (value) => '$value')}',
            ),
            Text(
              'Activity: ${_observationSummary(state, DeviceMetric.activityState, (value) => '$value')}',
            ),
            const SizedBox(height: AppSpacing.xs),
            if (location == null || !location.hasCoordinates)
              Text(
                'Location: ${location == null ? 'not shared' : _availabilityLabel(location.availability)}',
              )
            else ...[
              Text(
                'Location: available'
                '${location.approximate ? ' (approximate)' : ''}'
                '${location.accuracyMeters == null ? '' : ' ±${location.accuracyMeters!.round()}m'}',
              ),
              if (location.distanceFromHomeKm != null)
                Text(
                  'Distance from home: '
                  '${(location.distanceFromHomeKm! * 1000).round()}m'
                  '${location.accuracyMeters == null ? '' : ' (±${location.accuracyMeters!.round()}m)'}',
                ),
              if (location.presence != null)
                Text('At home: ${location.presence!.name}'),
              Text(
                'Location observed ${_relative(location.observedAt, now)} '
                '(${location.freshnessAt(now).name})',
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Last observed ${_relative(state.observedAt, now)} '
              '(${state.observationFreshnessAt(now).name})',
            ),
            Text(
              'Synchronized ${_relative(state.synchronizedAt, now)} '
              '(${state.synchronizationFreshnessAt(now).name})',
            ),
            if (state.stateVersion != null)
              Text('Partner state version: ${state.stateVersion}'),
            if (state.isFromCache)
              const Text(
                'Showing cached data: this is the last value this device '
                'received, not proof of the current state.',
              ),
            Text('Last confirmed online ${_relative(state.lastOnlineAt, now)}'),
          ],
        );
      },
    );
  }

  static String _observationSummary(
    RemoteDeviceState state,
    DeviceMetric metric,
    String Function(Object value) format,
  ) {
    final observation = state.observation(metric);
    if (observation.availability == CapabilityAvailability.available &&
        observation.value != null) {
      return format(observation.value!);
    }
    return _availabilityLabel(observation.availability);
  }

  static String _chargingSummary(RemoteDeviceState state) {
    final observation = state.observation(DeviceMetric.chargingState);
    if (observation.availability != CapabilityAvailability.available) {
      return _availabilityLabel(observation.availability);
    }
    return switch (observation.value) {
      'charging' => 'Charging',
      'discharging' => 'Not charging',
      _ => '${observation.value}',
    };
  }

  static String _availabilityLabel(CapabilityAvailability availability) =>
      switch (availability) {
        CapabilityAvailability.available => 'unknown',
        CapabilityAvailability.unavailable => 'not shared',
        CapabilityAvailability.unknown => 'unknown',
        CapabilityAvailability.unsupported => 'unsupported',
        CapabilityAvailability.permissionDenied => 'permission not granted',
        CapabilityAvailability.serviceDisabled => 'service disabled',
        CapabilityAvailability.error => 'unreadable',
        CapabilityAvailability.stale => 'stale',
      };

  static String _relative(DateTime? timestamp, DateTime now) {
    if (timestamp == null) return 'at an unknown time';
    final age = now.toUtc().difference(timestamp.toUtc());
    if (age.isNegative || age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}
