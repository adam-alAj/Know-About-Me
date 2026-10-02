import '../../../../core/domain/device_metric.dart';
import '../../../../core/freshness/data_freshness.dart';
import '../../../location/domain/models/location_state.dart';
import 'state_observation.dart';

/// One Firestore document exactly as the listener received it.
///
/// This is a *transport* envelope, not device state: it carries no validity
/// claim. [RemoteDeviceStateParser] turns it into a validated
/// [RemoteDeviceState], or rejects it.
///
/// The data layer converts Firestore `Timestamp`s into UTC `DateTime`s before
/// constructing this, so the domain layer stays pure Dart.
class RemoteStateDocument {
  const RemoteStateDocument({
    required this.data,
    required this.receivedAt,
    required this.isFromCache,
    this.hasPendingWrites = false,
  });

  /// A document that does not exist.
  const RemoteStateDocument.absent({
    required this.receivedAt,
    this.isFromCache = false,
    this.hasPendingWrites = false,
  }) : data = const <String, Object?>{};

  /// Raw field values, already converted to plain Dart types.
  final Map<String, Object?> data;

  /// This device's clock when the document arrived (Phase 11 §33).
  ///
  /// Distinct from the *partner's* observation time and from Firestore's
  /// synchronization time: it says when **we** learned the value, nothing more.
  final DateTime receivedAt;

  /// Whether Firestore served the value from its local cache.
  ///
  /// A cached document may be minutes or hours old, so it can never be treated
  /// as proof that the partner device is currently reachable (Phase 11 §31,
  /// §32).
  final bool isFromCache;

  /// Whether Firestore has yet to acknowledge local changes in this snapshot.
  final bool hasPendingWrites;

  /// Whether the document carries any state at all. A deleted document (for
  /// example after the partner stopped sharing location) is not an empty state.
  bool get exists => data.isNotEmpty;

  /// A safe, coordinate-free description.
  @override
  String toString() =>
      'RemoteStateDocument(exists: $exists, cached: $isFromCache, '
      'fields: ${data.length})';
}

/// The partner's location as synchronized, or the reason it is not available.
///
/// Coordinates are present only when the partner explicitly shares the
/// `location` category. [accuracyMeters] and [approximate] travel with the fix
/// so a reduced-accuracy position is never presented as precise (Phase 10 §7).
class RemoteLocationState {
  const RemoteLocationState({
    required this.availability,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.approximate = false,
    this.distanceFromHomeKm,
    this.presence,
    this.observedAt,
  });

  /// No location document exists, or it holds nothing usable.
  static const RemoteLocationState unavailable = RemoteLocationState(
    availability: CapabilityAvailability.unavailable,
  );

  /// The document exists but could not be parsed into a usable state.
  static const RemoteLocationState malformed = RemoteLocationState(
    availability: CapabilityAvailability.error,
  );

  final CapabilityAvailability availability;

  final double? latitude;
  final double? longitude;

  /// Platform-reported horizontal accuracy, or `null` when the partner's
  /// platform did not report one.
  final double? accuracyMeters;

  /// Whether the partner granted only approximate location.
  final bool approximate;

  /// Derived distance from the partner's home. Present only when the partner
  /// shares `distanceFromHome`; the home coordinates themselves are never
  /// synchronized (Phase 10 §16).
  final double? distanceFromHomeKm;

  /// The partner's own at-home classification, when it was computed.
  final HomePresence? presence;

  /// When the **partner's device** observed the fix, not when it was written.
  final DateTime? observedAt;

  /// Whether a usable coordinate pair is present.
  bool get hasCoordinates =>
      availability == CapabilityAvailability.available &&
      latitude != null &&
      longitude != null;

  /// Freshness of the partner's fix at [now], using the location policy.
  DataFreshness freshnessAt(DateTime now) {
    if (availability == CapabilityAvailability.stale) {
      return DataFreshness.stale;
    }
    final observed = observedAt;
    if (observed == null) return DataFreshness.unknown;
    return FreshnessPolicy.location.classifyAge(
      now.toUtc().difference(observed.toUtc()),
    );
  }

  /// A description that never prints coordinates.
  @override
  String toString() =>
      'RemoteLocationState(${availability.name}, '
      'accuracy: $accuracyMeters, approximate: $approximate)';
}

/// Validated partner device state, with both clocks attached.
///
/// Availability, timestamps and accuracy are preserved exactly as the partner
/// observed them: a value the partner could not produce stays `unsupported`, an
/// unknown status stays `unknown`, and a stale fix stays stale (Phase 11 §41).
class RemoteDeviceState {
  const RemoteDeviceState({
    required this.pairId,
    required this.ownerUserId,
    required this.observations,
    required this.schemaVersion,
    required this.receivedAt,
    required this.isFromCache,
    this.hasPendingWrites = false,
    this.deviceId,
    this.stateVersion,
    this.observedAt,
    this.synchronizedAt,
    this.lastOnlineAt,
    this.lastActivityAt,
    this.chargingStartedAt,
    this.location,
  });

  /// The pair this state was read through, so no consumer can be confused about
  /// which relationship authorized the read.
  final String pairId;

  /// The partner's user id, as stored by the partner's own device.
  final String ownerUserId;

  /// The partner's opaque app-generated device id, when published. Not a
  /// hardware identifier and not a credential.
  final String? deviceId;

  /// Every published metric, keyed by the shared [DeviceMetric] vocabulary.
  ///
  /// Absent metrics are `unavailable` rather than `unknown`/`false`: the
  /// partner either did not share that category or did not publish a value, and
  /// the application must not invent one.
  final Map<DeviceMetric, StateObservation<Object?>> observations;

  /// Monotonic per-device state version assigned by the publishing device.
  final int? stateVersion;

  /// Wire contract version, so an incompatible document fails safely.
  final int schemaVersion;

  /// When the **partner's device** observed the newest published value.
  final DateTime? observedAt;

  /// When **Firestore accepted the write** (server timestamp). Never a
  /// substitute for [observedAt] (Phase 11 §11, §13).
  final DateTime? synchronizedAt;

  /// The partner's last confirmed usable connectivity, from its own local
  /// monitoring. Not "the last time Firestore received a write" (Phase 11 §15).
  final DateTime? lastOnlineAt;

  /// When the partner's device last observed an activity signal.
  final DateTime? lastActivityAt;

  /// When the partner's device observed charging begin, when published.
  final DateTime? chargingStartedAt;

  /// When this device received the document [receivedAt].
  final DateTime receivedAt;

  /// Whether Firestore served the value from cache (Phase 11 §31).
  final bool isFromCache;

  /// Whether a component document contains local changes not yet acknowledged
  /// by Firestore. Kept separate from cache provenance.
  final bool hasPendingWrites;

  /// The partner's location, or why it is not available.
  final RemoteLocationState? location;

  /// Returns a copy with [value] attached.
  ///
  /// Used to merge the two synchronized documents (state and location) into one
  /// coherent picture without mutating either.
  RemoteDeviceState withLocation(
    RemoteLocationState? value, {
    bool? isFromCache,
    bool? hasPendingWrites,
  }) => RemoteDeviceState(
    pairId: pairId,
    ownerUserId: ownerUserId,
    deviceId: deviceId,
    observations: observations,
    stateVersion: stateVersion,
    schemaVersion: schemaVersion,
    observedAt: observedAt,
    synchronizedAt: synchronizedAt,
    lastOnlineAt: lastOnlineAt,
    lastActivityAt: lastActivityAt,
    chargingStartedAt: chargingStartedAt,
    receivedAt: receivedAt,
    // The merged state is cache-served if either constituent document is.
    // Otherwise a fresh state document could hide a cached location snapshot.
    isFromCache: isFromCache ?? this.isFromCache,
    hasPendingWrites: hasPendingWrites ?? this.hasPendingWrites,
    location: value,
  );

  /// A state document could not be read, but a location one could.
  ///
  /// Nothing is invented to fill the gap: the missing metrics stay absent, which
  /// surfaces as `unavailable`, and only the location facts the partner really
  /// published are reported.
  factory RemoteDeviceState.locationOnly({
    required String pairId,
    required String ownerUserId,
    required RemoteLocationState location,
    required int schemaVersion,
    required DateTime receivedAt,
    required bool isFromCache,
    bool hasPendingWrites = false,
    String? deviceId,
    int? stateVersion,
  }) => RemoteDeviceState(
    pairId: pairId,
    ownerUserId: ownerUserId,
    observations: const <DeviceMetric, StateObservation<Object?>>{},
    schemaVersion: schemaVersion,
    receivedAt: receivedAt,
    isFromCache: isFromCache,
    hasPendingWrites: hasPendingWrites,
    deviceId: deviceId,
    stateVersion: stateVersion,
    observedAt: location.observedAt,
    location: location,
  );

  /// Looks up one observation, defaulting to an explicit `unavailable`.
  StateObservation<Object?> observation(DeviceMetric metric) =>
      observations[metric] ??
      const StateObservation<Object?>(
        availability: CapabilityAvailability.unavailable,
      );

  /// Battery percentage, when present and valid.
  int? get batteryPercentage {
    final value = observation(DeviceMetric.batteryPercentage);
    return value.availability == CapabilityAvailability.available
        ? value.value as int?
        : null;
  }

  /// Charging state name (`charging`/`full`/`discharging`/`notCharging`), when
  /// published.
  String? get chargingState {
    final value = observation(DeviceMetric.chargingState);
    return value.availability == CapabilityAvailability.available
        ? value.value as String?
        : null;
  }

  /// Network status (`online`/`offline`/`unknown`), when published.
  String? get networkStatus {
    final value = observation(DeviceMetric.networkStatus);
    return value.availability == CapabilityAvailability.available
        ? value.value as String?
        : null;
  }

  /// Display state (`on`/`off`/`unknown`), when the partner published one.
  String? get screenState {
    final value = observation(DeviceMetric.screenState);
    return value.availability == CapabilityAvailability.available
        ? value.value as String?
        : null;
  }

  /// Availability evidence the partner published about itself.
  ///
  /// Never a power-state claim: an old document does not become "the phone is
  /// off" (Phase 11 §16).
  CapabilityAvailability get deviceAvailability {
    final value = observation(DeviceMetric.deviceAvailability);
    final published = value.value;
    if (value.availability != CapabilityAvailability.available ||
        published is! String) {
      return CapabilityAvailability.unknown;
    }
    return CapabilityAvailability.values.firstWhere(
      (candidate) => candidate.name == published,
      orElse: () => CapabilityAvailability.unknown,
    );
  }

  /// How current the partner's *observation* is.
  ///
  /// Falls back to the newest published observation when the document has no
  /// top-level timestamp, so a partially published state is not reported as
  /// having no time at all.
  DataFreshness observationFreshnessAt(DateTime now) {
    final observed = observedAt ?? _newestObservationTime();
    if (observed == null) return DataFreshness.unknown;
    return FreshnessPolicy.standard.classifyAge(
      now.toUtc().difference(observed.toUtc()),
    );
  }

  /// How current the *synchronization* is, separately from the observation.
  ///
  /// A partner state can be freshly synchronized while carrying an old
  /// observation, and the reverse; the two are never collapsed (Phase 11 §33).
  DataFreshness synchronizationFreshnessAt(DateTime now) {
    final synchronized = synchronizedAt;
    if (synchronized == null) return DataFreshness.unknown;
    return FreshnessPolicy.standard.classifyAge(
      now.toUtc().difference(synchronized.toUtc()),
    );
  }

  DateTime? _newestObservationTime() {
    DateTime? newest;
    for (final observation in observations.values) {
      final time = observation.observedAt;
      if (time == null) continue;
      if (newest == null || time.isAfter(newest)) newest = time;
    }
    return newest;
  }

  /// A safe description that never includes coordinates.
  @override
  String toString() =>
      'RemoteDeviceState(owner: $ownerUserId, version: $stateVersion, '
      'fields: ${observations.length})';
}

/// Explicit marker for state received from an authorized partner.
///
/// It exists so partner data can never be passed where local state is expected
/// (Phase 11 §5). The two are separate concepts and must stay separate.
class PartnerDeviceState {
  const PartnerDeviceState(this.state);

  final RemoteDeviceState state;

  @override
  String toString() => 'PartnerDeviceState($state)';
}
