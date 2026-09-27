import '../../../../core/freshness/data_freshness.dart';
import '../models/device_availability_evidence.dart';
import '../models/state_observation.dart';

/// Derives local device availability from observed evidence (Phase 9).
///
/// The rules are deliberately conservative:
///
/// * Availability is `available` only when some observation (or a restored
///   `lastObservedActivityAt`) confirmed a valid signal within the freshness
///   window; older evidence becomes `stale` while keeping the historical
///   confirmation time.
/// * With no positive evidence, the structural reason of the underlying
///   observations wins: `unsupported`, `permissionDenied`, `error` or
///   `unavailable`, in that order; only a genuinely empty picture is
///   `unknown`.
/// * There is no power-state claim: missing evidence never becomes
///   "phone off". See `docs/device-state/ACTIVITY_AVAILABILITY.md`.
class DeviceAvailabilityDeriver {
  const DeviceAvailabilityDeriver();

  DeviceAvailabilityEvidence derive({
    required Iterable<StateObservation<Object?>> observations,
    DateTime? lastObservedActivityAt,
    required DateTime now,
  }) {
    final at = now.toUtc();

    DateTime? newest;
    for (final observation in observations) {
      if (observation.availability != CapabilityAvailability.available) {
        continue;
      }
      final timestamp = observation.observedAt?.toUtc();
      if (timestamp != null && (newest == null || timestamp.isAfter(newest))) {
        newest = timestamp;
      }
    }
    final activityEvidence = lastObservedActivityAt?.toUtc();
    if (activityEvidence != null &&
        (newest == null || activityEvidence.isAfter(newest))) {
      newest = activityEvidence;
    }

    if (newest != null) {
      final age = at.difference(newest);
      final withinWindow = age <= FreshnessPolicy.standard.recentFor;
      return DeviceAvailabilityEvidence(
        availability: withinWindow
            ? CapabilityAvailability.available
            : CapabilityAvailability.stale,
        lastConfirmedAvailableAt: newest,
        observedAt: at,
        source: 'local_observations',
      );
    }

    final availabilities = observations
        .map((observation) => observation.availability)
        .toSet();
    if (availabilities.isEmpty) {
      return DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: 'local_observations',
      );
    }
    if (availabilities.every(
      (value) => value == CapabilityAvailability.unsupported,
    )) {
      return DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.unsupported,
        observedAt: at,
        source: 'local_observations',
      );
    }
    if (availabilities.contains(CapabilityAvailability.permissionDenied)) {
      return DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.permissionDenied,
        observedAt: at,
        source: 'local_observations',
      );
    }
    String? firstError;
    for (final observation in observations) {
      if (observation.availability == CapabilityAvailability.error) {
        firstError = observation.error;
        break;
      }
    }
    if (availabilities.contains(CapabilityAvailability.error)) {
      return DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: 'local_observations',
        error: firstError ?? 'A device-state observation failed.',
      );
    }
    if (availabilities.contains(CapabilityAvailability.unavailable)) {
      return DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.unavailable,
        observedAt: at,
        source: 'local_observations',
      );
    }
    return DeviceAvailabilityEvidence(
      availability: CapabilityAvailability.unknown,
      observedAt: at,
      source: 'local_observations',
    );
  }
}
