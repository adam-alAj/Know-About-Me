/// Stores only the most recent time an online state was observed. It does not
/// persist current status or offline start, which must be re-established after
/// process/lifecycle gaps.
abstract interface class NetworkObservationStore {
  Future<DateTime?> readLastOnlineAt();
  Future<void> writeLastOnlineAt(DateTime value);
}
