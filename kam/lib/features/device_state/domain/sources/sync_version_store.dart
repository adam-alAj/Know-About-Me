/// Persists the monotonic state version this device stamps on its writes.
///
/// The version exists so an older local snapshot can be recognised as older
/// rather than silently overwriting a newer one (Phase 11 §12, §49). It is a
/// local counter, not a credential: it grants nothing.
abstract interface class SyncVersionStore {
  /// The last version this device issued, or `0` when none has been issued.
  Future<int> read();

  /// Records the newest issued version.
  Future<void> write(int version);
}
