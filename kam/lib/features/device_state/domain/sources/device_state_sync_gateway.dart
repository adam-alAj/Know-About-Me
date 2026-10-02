import '../models/remote_device_state.dart';
import '../models/sync_payload.dart';

/// What happened to one synchronized document.
enum SyncWriteStatus { published, deleted, failed }

/// The result of attempting one write, including why it failed.
///
/// Failure reasons are technical and safe to surface: they never contain
/// coordinates or other data values (NFR-045).
class SyncWriteResult {
  const SyncWriteResult(this.status, {this.reason});

  const SyncWriteResult.published()
    : status = SyncWriteStatus.published,
      reason = null;
  const SyncWriteResult.deleted()
    : status = SyncWriteStatus.deleted,
      reason = null;
  const SyncWriteResult.failed(this.reason) : status = SyncWriteStatus.failed;

  final SyncWriteStatus status;
  final String? reason;

  bool get isFailure => status == SyncWriteStatus.failed;

  @override
  String toString() =>
      'SyncWriteResult(${status.name}${reason == null ? '' : ': $reason'})';
}

/// The Firestore boundary for device-state synchronization.
///
/// The gateway only moves bytes: it never decides *what* may be shared. That
/// decision lives in the sanitizer, and the authoritative enforcement lives in
/// Firestore Security Rules. A gateway that is handed a payload it may not
/// write must fail with `permission-denied` rather than work around it.
abstract interface class DeviceStateSyncGateway {
  /// Writes, or removes, one document for [ownerId] inside [pairId].
  ///
  /// A retracted payload deletes the document. The gateway must never accept
  /// `ownerId` from user input: it is supplied by the caller from authenticated
  /// application state (Phase 11 §22, §50).
  Future<SyncWriteResult> publish({
    required String pairId,
    required String ownerId,
    required SyncPayload payload,
  });

  /// Watches one document for a given owner.
  ///
  /// Emits the current value immediately when one exists, then every server
  /// change. Documents served from the local cache are marked
  /// [RemoteStateDocument.isFromCache] so cached data is never mistaken for
  /// current state (Phase 11 §31).
  Stream<RemoteStateDocument> watch({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  });

  /// Reads directly from the Firestore server. Unlike [watch], this does not
  /// fall back to cached data when the server cannot be reached.
  Future<RemoteStateDocument> readFromServer({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  });
}
