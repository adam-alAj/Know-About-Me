import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/firebase/firebase_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../pairing/presentation/providers/pairing_providers.dart';
import '../../data/repositories/firestore_partner_device_state_repository.dart';
import '../../data/repositories/firestore_sharing_repository.dart';
import '../../data/services/shared_preferences_sync_version_store.dart';
import '../../data/sync/device_state_sync_coordinator.dart';
import '../../data/sync/firestore_device_state_sync_gateway.dart';
import '../../domain/models/pair_sharing_state.dart';
import '../../domain/models/remote_device_state.dart';
import '../../domain/repositories/partner_device_state_repository.dart';
import '../../domain/repositories/sharing_repository.dart';
import '../../domain/services/device_state_sanitizer.dart';
import '../../domain/services/device_state_sync_service.dart';
import '../../domain/sources/device_state_sync_gateway.dart';
import 'device_state_providers.dart';

/// The Firestore boundary for synchronization, or `null` when Firebase is
/// unavailable in this build.
///
/// Every other provider here degrades to a no-op rather than throwing, so a
/// build without Firebase still runs: it simply never shares anything.
final deviceStateSyncGatewayProvider = Provider<DeviceStateSyncGateway?>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) return null;
  return FirestoreDeviceStateSyncGateway(
    ref.watch(firebaseFirestoreProvider),
    now: () => ref.read(clockProvider).nowUtc(),
  );
});

/// Publishes this device's own state to the active pair.
final deviceStateSyncServiceProvider = Provider<DeviceStateSyncService?>((ref) {
  final gateway = ref.watch(deviceStateSyncGatewayProvider);
  if (gateway == null) return null;
  final service = DeviceStateSyncService(
    syncGateway: gateway,
    stateSanitizer: DeviceStateSanitizer(
      now: () => ref.read(clockProvider).nowUtc(),
    ),
    versionCounter: SharedPreferencesSyncVersionStore(),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Reads and writes this member's sharing switches for the active pair.
final sharingRepositoryProvider = Provider<SharingRepository?>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) return null;
  return FirestoreSharingRepository(ref.watch(firebaseFirestoreProvider));
});

/// The signed-in user's own sharing switches.
///
/// Resolves to [PairSharingState.none] whenever anything is unknown — no pair,
/// no Firebase, no document, or a failed read. Sharing therefore fails closed:
/// nothing is published until the user has explicitly enabled it.
final ownSharingProvider = StreamProvider<PairSharingState>((ref) {
  final scope = ref.watch(partnerScopeProvider).value;
  final repository = ref.watch(sharingRepositoryProvider);
  final uid = ref.watch(currentIdentityProvider)?.uid;
  if (scope == null || repository == null || uid == null) {
    return Stream<PairSharingState>.value(PairSharingState.none);
  }
  return repository.watch(pairId: scope.pairId, userId: uid);
});

/// Reads the authorized partner's synchronized state.
final partnerDeviceStateRepositoryProvider =
    Provider<PartnerDeviceStateRepository?>((ref) {
      if (!ref.watch(firebaseAvailableProvider)) return null;
      final gateway = ref.watch(deviceStateSyncGatewayProvider);
      if (gateway == null) return null;
      return FirestorePartnerDeviceStateRepository(gateway);
    });

/// The partner's current synchronized state, or `null` when there is nothing to
/// show (no active pair, or the partner has never published).
///
/// The stream is recreated when the pair or the partner changes, and the old
/// listener is cancelled by the provider scope, so exactly one partner-state
/// listener is alive at a time (Phase 11 §21).
final partnerDeviceStateProvider = StreamProvider<PartnerDeviceState?>((ref) {
  final scope = ref.watch(partnerScopeProvider).value;
  final repository = ref.watch(partnerDeviceStateRepositoryProvider);
  if (scope == null || repository == null) {
    return Stream<PartnerDeviceState?>.value(null);
  }
  return repository.watch(
    pairId: scope.pairId,
    partnerUserId: scope.partnerUserId,
  );
});

/// The outcome of each completed synchronization run.
final deviceStateSyncResultsProvider = StreamProvider<List<SyncOutcome>>((ref) {
  final service = ref.watch(deviceStateSyncServiceProvider);
  if (service == null) return Stream<List<SyncOutcome>>.value(const []);
  return service.results;
});

/// Connects local observations to the synchronization pipeline.
///
/// Instantiated (watched) from the application root so it lives exactly as long
/// as the app does. It is inert without an authorized pair: no pair means no
/// writes and no partner listener.
final deviceStateSyncCoordinatorProvider = Provider<DeviceStateSyncCoordinator?>(
  (ref) {
    final service = ref.watch(deviceStateSyncServiceProvider);
    if (service == null) return null;

    final coordinator = DeviceStateSyncCoordinator(service);
    ref.onDispose(() => unawaited(coordinator.stop()));

    ref.listen(partnerScopeProvider, (_, next) {
      unawaited(coordinator.updateScope(next.value));
    }, fireImmediately: true);

    ref.listen(ownSharingProvider, (_, next) {
      coordinator.updateSharing(next.value ?? PairSharingState.none);
    }, fireImmediately: true);

    ref.listen(monitoredDeviceStateProvider, (_, next) {
      final snapshot = next.value;
      if (snapshot != null) coordinator.onLocalSnapshot(snapshot);
    });

    return coordinator;
  },
);
