import 'dart:async';

import '../../../pairing/domain/models/partner_scope.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/models/pair_sharing_state.dart';
import '../../domain/services/device_state_sync_service.dart';

/// Routes local state changes into the synchronization service.
///
/// It holds the current *authorization context* — which pair, which partner, and
/// what the owner currently shares — and does nothing at all without one. That
/// makes the safety property explicit: no pair, no write.
///
/// It performs no I/O of its own, so it is fully testable with a fake gateway.
class DeviceStateSyncCoordinator {
  DeviceStateSyncCoordinator(this._service);

  final DeviceStateSyncService _service;

  PartnerScope? _scope;
  PairSharingState _sharing = PairSharingState.none;
  DeviceStateSnapshot? _latestSnapshot;

  /// The pair currently being synchronized, or `null`.
  PartnerScope? get scope => _scope;

  /// Whether a synchronization target is currently authorized.
  bool get isActive => _scope != null && _sharing.sharesAnything;

  /// Points the coordinator at the resolved active pair.
  ///
  /// Changing the pair discards all publication bookkeeping: signatures and the
  /// version counter belong to one relationship, and reusing them across a pair
  /// change could either skip a needed write or delete a document this device
  /// never wrote.
  Future<void> updateScope(PartnerScope? scope) async {
    if (scope == _scope) return;
    _scope = scope;
    _latestSnapshot = null;
    await _service.reset();
  }

  /// Applies a sharing snapshot this device could actually confirm.
  ///
  /// `null` means **unknown**, not "nothing is shared": the snapshot was served
  /// from Firestore's local cache with no local write pending, so it is the last
  /// known setting rather than a decision. Treating that as "share nothing"
  /// would retract the user's own published documents merely because the device
  /// went offline — a spurious delete that the partner sees, followed by a
  /// republish when the connection returns (Phase 20 §11, §27). The last applied
  /// sharing therefore stays in force until a confirmed value arrives.
  void applyConfirmedSharing(PairSharingState? sharing) {
    if (sharing == null) return;
    updateSharing(sharing);
  }

  /// Applies the owner's current sharing switches.
  void updateSharing(PairSharingState sharing) {
    if (sharing.paused == _sharing.paused &&
        sharing.categories.length == _sharing.categories.length &&
        sharing.categories.containsAll(_sharing.categories)) {
      return;
    }
    _sharing = sharing;
    final snapshot = _latestSnapshot;
    if (snapshot != null) onLocalSnapshot(snapshot);
  }

  /// Offers a freshly observed local snapshot for publication.
  ///
  /// Called on every local change; the service decides whether anything
  /// actually needs to be written.
  void onLocalSnapshot(DeviceStateSnapshot snapshot) {
    final previous = _latestSnapshot;
    _latestSnapshot = snapshot;
    final scope = _scope;
    if (scope == null) return;
    final request = SyncRequest(
      pairId: scope.pairId,
      snapshot: snapshot,
      sharedCategories: _sharing.categories,
      sharingPaused: _sharing.paused,
    );
    if (_isSignificantTransition(previous, snapshot)) {
      // Publish meaningful screen/charging transitions at once rather than
      // after the coalescing window. The coalescing timer does not run while the
      // process is backgrounded, so leaving a screen-off transition to the
      // timer would mean the partner never saw the change. The change tracker
      // still prevents a duplicate write from a later trigger.
      unawaited(
        _service.publishNow(
          pairId: request.pairId,
          snapshot: request.snapshot,
          sharedCategories: request.sharedCategories,
          sharingPaused: request.sharingPaused,
        ),
      );
      return;
    }
    _service.requestPublish(request);
  }

  /// Whether [current] carries a transition the partner needs promptly.
  ///
  /// Only discrete state changes qualify. Battery level and other continuously
  /// varying values stay on the coalesced path, so a burst of readings still
  /// produces at most one write.
  static bool _isSignificantTransition(
    DeviceStateSnapshot? previous,
    DeviceStateSnapshot current,
  ) {
    if (previous == null) return false;
    final beforeScreen = previous.activity?.screenState.value;
    final afterScreen = current.activity?.screenState.value;
    if (beforeScreen != null && afterScreen != null && beforeScreen != afterScreen) {
      return true;
    }
    final beforeCharging = previous.battery?.chargingState.value;
    final afterCharging = current.battery?.chargingState.value;
    if (beforeCharging != null &&
        afterCharging != null &&
        beforeCharging != afterCharging) {
      return true;
    }
    return false;
  }

  /// Re-requests publication of the latest snapshot.
  ///
  /// Called when the application resumes or the connection returns. It gives a
  /// bounded retry chain a new trigger without replaying anything: the service
  /// still publishes only the *latest* state, and only if the meaningful
  /// content actually changed (Phase 20 §20, §22, §27).
  void reassertLatest() {
    final snapshot = _latestSnapshot;
    if (snapshot != null) onLocalSnapshot(snapshot);
  }

  /// Publishes immediately, bypassing coalescing.
  Future<List<SyncOutcome>> publishNow(DeviceStateSnapshot snapshot) async {
    final scope = _scope;
    if (scope == null) return const <SyncOutcome>[];
    _latestSnapshot = snapshot;
    return _service.publishNow(
      pairId: scope.pairId,
      snapshot: snapshot,
      sharedCategories: _sharing.categories,
      sharingPaused: _sharing.paused,
    );
  }

  /// Reconciles a freshly collected local snapshot through the same authorized
  /// publish pipeline used for automatic observations. Unlike [reassertLatest],
  /// this always advances the coordinator's snapshot before writing.
  Future<List<SyncOutcome>> reconcileNow(DeviceStateSnapshot snapshot) =>
      publishNow(snapshot);

  /// Stops synchronizing, for example on sign-out or when the pair ends.
  Future<void> stop() async {
    _scope = null;
    _sharing = PairSharingState.none;
    _latestSnapshot = null;
    await _service.reset();
  }
}
