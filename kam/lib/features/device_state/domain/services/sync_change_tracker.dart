import '../models/sync_payload.dart';

/// Remembers what was last successfully published, so an unchanged value never
/// causes a second Firestore write (Phase 11 §7).
///
/// Only *successful* writes are recorded. A failed write leaves the previous
/// signature untouched, so the next trigger retries the **latest** state rather
/// than replaying every intermediate one (Phase 11 §18, §19).
class SyncChangeTracker {
  final Map<SyncDocumentKind, String> _published = <SyncDocumentKind, String>{};

  /// Whether [payload] differs from what was last published for its document.
  bool hasChanged(SyncPayload payload) =>
      _published[payload.kind] != payload.signature();

  /// Whether anything has ever been published for [kind].
  ///
  /// Used to decide whether a retraction needs to delete a document at all.
  bool hasPublished(SyncDocumentKind kind) => _published.containsKey(kind);

  /// Records a payload as successfully published.
  void recordPublished(SyncPayload payload) {
    _published[payload.kind] = payload.signature();
  }

  /// Forgets one document, for example after the pair ended or the user signed
  /// out, so a later session cannot treat stale bookkeeping as up to date.
  void forget(SyncDocumentKind kind) => _published.remove(kind);

  /// Forgets everything. Used when the active pair changes or on sign-out.
  void reset() => _published.clear();

  @override
  String toString() => 'SyncChangeTracker(published: ${_published.length})';
}
