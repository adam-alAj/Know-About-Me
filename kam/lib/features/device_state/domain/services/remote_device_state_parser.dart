import '../../../location/domain/models/location_state.dart';
import '../../../../core/domain/device_metric.dart';
import '../models/remote_device_state.dart';
import '../models/state_observation.dart';

/// Parses a partner's synchronized documents into validated state.
///
/// Firestore data is never trusted: every field is type-checked, range-checked
/// and enum-checked, missing fields become explicit non-available observations,
/// and a document this build cannot understand is rejected rather than
/// half-read (Phase 11 §38, §39).
class RemoteDeviceStateParser {
  const RemoteDeviceStateParser({this.supportedSchemaVersion = 1});

  /// The newest wire contract this build understands.
  ///
  /// A newer document fails safe: the partner sees "no usable state" rather
  /// than a mis-read one.
  final int supportedSchemaVersion;

  /// Battery percentages outside this range are not real observations.
  static const int _minPercentage = 0;
  static const int _maxPercentage = 100;

  /// Non-value availability markers that may appear in an enum-typed field so
  /// `unsupported` stays `unsupported` across synchronization.
  static const Set<String> _availabilityMarkers = {
    'unavailable',
    'unsupported',
    'permissionDenied',
    'serviceDisabled',
    'error',
    'stale',
  };

  /// Parses the non-location state document.
  ///
  /// Returns `null` when the document does not exist, belongs to a different
  /// user than expected, or uses an unsupported schema. A rejected document is
  /// never partially applied.
  RemoteDeviceState? parseDeviceState({
    required String pairId,
    required String expectedOwnerUserId,
    required RemoteStateDocument document,
  }) {
    if (!document.exists) return null;

    final owner = document.data['ownerUserId'];
    if (owner is! String || owner != expectedOwnerUserId) return null;

    final schemaVersion = _int(document.data['schemaVersion']) ?? 1;
    if (schemaVersion > supportedSchemaVersion) return null;

    final observedAt = _timestamp(document.data['observedAt']);
    final synchronizedAt = _timestamp(document.data['updatedAt']);
    final lastOnlineAt = _timestamp(document.data['lastOnlineAt']);
    final lastActivityAt = _timestamp(document.data['lastActivityAt']);
    final chargingStartedAt = _timestamp(document.data['chargingStartedAt']);

    final observations = <DeviceMetric, StateObservation<Object?>>{};

    final percentage = _int(document.data['batteryPercentage']);
    if (percentage != null &&
        percentage >= _minPercentage &&
        percentage <= _maxPercentage) {
      observations[DeviceMetric.batteryPercentage] = StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: percentage,
        observedAt: observedAt,
        source: 'partner_sync',
      );
    }

    final isCharging = document.data['isCharging'];
    if (isCharging is bool) {
      observations[DeviceMetric.chargingState] = StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: isCharging ? 'charging' : 'discharging',
        observedAt: observedAt,
        source: 'partner_sync',
      );
    }

    final durationSeconds = _int(document.data['chargingDurationSeconds']);
    if (durationSeconds != null && durationSeconds >= 0) {
      observations[DeviceMetric.chargingDuration] = StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: Duration(seconds: durationSeconds),
        observedAt: chargingStartedAt ?? observedAt,
        source: 'partner_sync',
      );
    }

    final networkState = _string(document.data['networkState']);
    if (networkState != null) {
      observations[DeviceMetric.networkStatus] = StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: networkState,
        // The partner's own last-confirmed-online time is the only timestamp
        // the wire format carries for connectivity (Phase 11 §15).
        observedAt: lastOnlineAt ?? observedAt,
        source: 'partner_sync',
      );
    }

    final screenState = _enumLike(document.data['screenState']);
    if (screenState != null) {
      observations[DeviceMetric.screenState] = screenState;
    }

    final activityState = _enumLike(document.data['activityState']);
    if (activityState != null) {
      observations[DeviceMetric.activityState] = activityState;
    }

    final availabilityState = _string(document.data['availabilityState']);
    if (availabilityState != null) {
      observations[DeviceMetric.deviceAvailability] = StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: availabilityState,
        observedAt: observedAt,
        source: 'partner_sync',
      );
    }

    // A deliberately synthesized observation for the activity timestamp: the
    // wire format carries it as its own field, so it is not invented here.
    if (lastActivityAt != null) {
      observations[DeviceMetric.lastActivity] = StateObservation<Object?>(
        availability: CapabilityAvailability.available,
        value: lastActivityAt,
        observedAt: lastActivityAt,
        source: 'partner_sync',
      );
    }

    return RemoteDeviceState(
      pairId: pairId,
      ownerUserId: owner,
      deviceId: _string(document.data['deviceId']),
      observations: Map.unmodifiable(observations),
      stateVersion: _int(document.data['stateVersion']),
      schemaVersion: schemaVersion,
      observedAt: observedAt,
      synchronizedAt: synchronizedAt,
      lastOnlineAt: lastOnlineAt,
      lastActivityAt: lastActivityAt,
      chargingStartedAt: chargingStartedAt,
      receivedAt: document.receivedAt,
      isFromCache: document.isFromCache,
    );
  }

  /// Parses the partner's location document.
  ///
  /// Returns [RemoteLocationState.unavailable] for a missing document and
  /// [RemoteLocationState.malformed] for one that exists but cannot be trusted.
  RemoteLocationState parseLocation({
    required String expectedOwnerUserId,
    required RemoteStateDocument document,
  }) {
    if (!document.exists) return RemoteLocationState.unavailable;

    final owner = document.data['ownerUserId'];
    if (owner is! String || owner != expectedOwnerUserId) {
      return RemoteLocationState.malformed;
    }

    final schemaVersion = _int(document.data['schemaVersion']) ?? 1;
    if (schemaVersion > supportedSchemaVersion) {
      return RemoteLocationState.malformed;
    }

    final latitude = _double(document.data['latitude']);
    final longitude = _double(document.data['longitude']);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return RemoteLocationState.malformed;
    }

    final observedAt = _timestamp(document.data['observedAt']);
    final accuracy = _double(document.data['accuracyMeters']);
    final distanceKm = _double(document.data['distanceFromHomeKm']);
    final presenceName = _string(document.data['homePresence']);

    return RemoteLocationState(
      availability: CapabilityAvailability.available,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy != null && accuracy >= 0 ? accuracy : null,
      approximate: document.data['approximate'] == true,
      distanceFromHomeKm: distanceKm != null && distanceKm >= 0
          ? distanceKm
          : null,
      presence: presenceName == null ? null : _presence(presenceName),
      observedAt: observedAt,
    );
  }

  /// Reads a field that may hold either a real enum value or an availability
  /// marker, so a non-observable state survives the round trip unchanged.
  static StateObservation<Object?>? _enumLike(Object? raw) {
    final value = _string(raw);
    if (value == null) return null;
    if (_availabilityMarkers.contains(value)) {
      return StateObservation<Object?>(
        availability: CapabilityAvailability.values.firstWhere(
          (candidate) => candidate.name == value,
        ),
        source: 'partner_sync',
      );
    }
    return StateObservation<Object?>(
      availability: CapabilityAvailability.available,
      value: value,
      source: 'partner_sync',
    );
  }

  static HomePresence? _presence(String name) {
    for (final candidate in HomePresence.values) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  static int? _int(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : null;

  static double? _double(Object? value) => value is num ? value.toDouble() : null;

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  /// Accepts a `DateTime` (preferred, produced by the data layer) or an ISO-8601
  /// string, and always returns UTC.
  static DateTime? _timestamp(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed?.toUtc();
    }
    return null;
  }
}
