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
    _latestSnapshot = snapshot;
    final scope = _scope;
    if (scope == null) return;
    _service.requestPublish(
      SyncRequest(
        pairId: scope.pairId,
        snapshot: snapshot,
        sharedCategories: _sharing.categories,
        sharingPaused: _sharing.paused,
      ),
    );
  }

  /// Publishes immediately, bypassing coalescing.
  Future<List<SyncOutcome>> publishNow(DeviceStateSnapshot snapshot) async {
    final scope = _scope;
    if (scope == null) return const <SyncOutcome>[];
    return _service.publishNow(
      pairId: scope.pairId,
      snapshot: snapshot,
      sharedCategories: _sharing.categories,
      sharingPaused: _sharing.paused,
    );
  }

  /// Stops synchronizing, for example on sign-out or when the pair ends.
  Future<void> stop() async {
    _scope = null;
    _sharing = PairSharingState.none;
    _latestSnapshot = null;
    await _service.reset();
  }
}
