import '../models/device_location_state.dart';

/// Stores exactly one thing: the most recent location fix.
///
/// This is deliberately not a location history database (Phase 10 §23, §26).
/// The stored fix keeps its original platform timestamp, so a restored fix is
/// reported with its real age and classified `stale` when appropriate.
abstract interface class LocationObservationStore {
  Future<LocationFix?> readLastKnownFix();
  Future<void> writeLastKnownFix(LocationFix fix);
}
