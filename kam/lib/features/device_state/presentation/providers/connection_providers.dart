import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/connectivity/connection_status.dart';
import '../../../pairing/domain/models/pair_membership.dart';
import '../../../pairing/presentation/providers/pairing_providers.dart';
import '../../domain/services/device_state_sync_service.dart';
import 'sync_providers.dart';

/// Whether the synchronization service is writing right now.
///
/// The service's `busy` stream is a broadcast stream with no initial value, so
/// it is seeded from the service's current state; without that, the indicator
/// would briefly claim nothing is happening on a warm start.
final deviceStateSyncBusyProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(deviceStateSyncServiceProvider);
  if (service == null) return Stream<bool>.value(false);
  return _busy(service);
});

Stream<bool> _busy(DeviceStateSyncService service) async* {
  yield service.isBusy;
  yield* service.busy;
}

/// Everything the connection status is allowed to be derived from.
///
/// This is the *only* place connection state is decided. Every input is real
/// evidence — snapshot metadata, a write outcome, an in-flight run — so the
/// derivation can never turn "I have not heard anything" into "offline"
/// (Phase 20 §9, §23).
final connectionEvidenceProvider = Provider<ConnectionEvidence>((ref) {
  final memberships =
      ref.watch(pairMembershipsProvider).value ?? const <PairMembership>[];
  final partnerState = ref.watch(partnerDeviceStateProvider).value;
  final ownSharing = ref.watch(ownSharingProvider).value;
  final partnerSharing = ref.watch(partnerSharingProvider).value;
  final outcomes =
      ref.watch(deviceStateSyncResultsProvider).value ?? const <SyncOutcome>[];
  final isSyncing = ref.watch(deviceStateSyncBusyProvider).value ?? false;

  // Only *our own* unacknowledged write is treated as offline evidence. The
  // default `PairSharingState.none` a provider emits when there is no pair
  // carries `hasPendingWrites: false`, so it can never be mistaken for one.
  final hasPendingWrites =
      memberships.any((membership) => membership.hasPendingWrites) ||
      (ownSharing?.hasPendingWrites ?? false) ||
      (partnerSharing?.hasPendingWrites ?? false);

  final hasServerConfirmedDocument =
      memberships.any((membership) => !membership.isFromCache) ||
      (partnerState != null && !partnerState.state.isFromCache);

  return ConnectionEvidence(
    hasAnyDocument: memberships.isNotEmpty || partnerState != null,
    hasServerConfirmedDocument: hasServerConfirmedDocument,
    hasPendingWrites: hasPendingWrites,
    isSyncing: isSyncing,
    hasRetryableFailure: outcomes.any((outcome) => outcome.isRetryable),
    hasNetworkFailure: outcomes.any(
      (outcome) =>
          outcome.isRetryable &&
          outcome.failureKind == SyncFailureKind.transient,
    ),
    hasBlockedWrite: outcomes.any((outcome) => outcome.isBlocked),
  );
});

/// The application's connection, synchronization and recovery state.
final connectionStatusProvider =
    NotifierProvider<ConnectionStatusController, ConnectionStatus>(
      ConnectionStatusController.new,
    );

/// Derives [ConnectionStatus] and remembers whether a reconnection happened.
///
/// The derivation itself is a pure function of [ConnectionEvidence]; the only
/// state this controller owns is the *transition* the evidence cannot express —
/// "we were offline, and now we are not". That is what lets the UI say
/// "catching up" instead of pretending the first post-reconnect snapshot is
/// already current.
class ConnectionStatusController extends Notifier<ConnectionStatus> {
  ConnectionRecovery _recovery = const ConnectionRecovery();

  @override
  ConnectionStatus build() {
    final evidence = ref.watch(connectionEvidenceProvider);
    _recovery = _recovery.observe(evidence);
    return evidence.status(recovery: _recovery.state);
  }

  /// Re-derives from the evidence already held.
  ///
  /// Used when the app resumes. It re-runs the derivation *only*; it never
  /// re-subscribes a listener, because invalidating the evidence's own providers
  /// would recreate Firestore listeners and risk duplicates (Phase 20 §21).
  void refresh() => ref.invalidateSelf();
}
