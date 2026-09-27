/// Stores only the most recent timestamp at which a supported activity signal
/// was observed.
///
/// Deliberately minimal (Phase 9): no activity history, no timeline, no
/// per-event log. On restart the value is restored at its historical time so
/// the system can mark it stale instead of pretending it is current.
abstract interface class ActivityObservationStore {
  Future<DateTime?> readLastObservedActivityAt();
  Future<void> writeLastObservedActivityAt(DateTime value);
}
