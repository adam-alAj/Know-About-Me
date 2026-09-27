import '../../../privacy/domain/models/sharing_category.dart';
import '../models/activity_state.dart';
import '../models/battery_state.dart';
import '../models/device_state_snapshot.dart';
import '../models/network_state.dart';
import '../models/sync_payload.dart';

/// Turns a local device-state snapshot into a validated, category-filtered
/// write payload.
///
/// This is the single place where "what this device can observe" becomes "what
/// may leave this device". It is deliberately pure: no Firebase, no clock, no
/// I/O, so every rule below is unit-testable and the published document can
/// never contain a value the device could not attest.
///
/// Rules applied:
/// * a field is published only when its [SharingCategory] is enabled and
///   sharing is not paused;
/// * a field whose category is **not** enabled is added to
///   [SyncPayload.clearedFields] so previously exposed data is retracted, not
///   merely hidden;
/// * values outside their valid range (battery outside 0–100, non-finite or
///   out-of-range coordinates, negative accuracy) are dropped rather than
///   clamped or corrected (Phase 11 §37);
/// * an unobservable value is never converted into a confident one — an unknown
///   charging state does not become `false`, and an unsupported display state is
///   published *as* `unsupported` so the partner sees the same truth
///   (Phase 11 §41).
class DeviceStateSanitizer {
  const DeviceStateSanitizer({required this.now, this.schemaVersion = 1});

  /// The application clock, injected so a future timestamp can be rejected
  /// deterministically instead of depending on the wall clock at test time.
  final DateTime Function() now;

  /// Wire contract version written into every document.
  final int schemaVersion;

  /// Categories whose fields live in the `deviceState` document.
  static const Set<SharingCategory> _deviceStateCategories = {
    SharingCategory.battery,
    SharingCategory.charging,
    SharingCategory.network,
    SharingCategory.activityIndicators,
  };

  /// Sanitizes the non-location state document.
  SyncPayload sanitizeDeviceState({
    required DeviceStateSnapshot snapshot,
    required String ownerUserId,
    required Set<SharingCategory> sharedCategories,
    required bool sharingPaused,
    required int stateVersion,
  }) {
    final shareable =
        !sharingPaused &&
        sharedCategories.any(_deviceStateCategories.contains);
    if (!shareable) {
      return const SyncPayload.retracted(kind: SyncDocumentKind.deviceState);
    }

    final fields = <String, Object?>{
      'ownerUserId': ownerUserId,
      'schemaVersion': schemaVersion,
      'stateVersion': stateVersion,
    };
    final cleared = <String>{};

    void put(String field, SharingCategory category, Object? value) {
      if (value == null) {
        cleared.add(field);
        return;
      }
      if (!sharedCategories.contains(category)) {
        cleared.add(field);
        return;
      }
      fields[field] = value;
    }

    final battery = snapshot.battery;
    put(
      'batteryPercentage',
      SharingCategory.battery,
      _percentage(battery?.percentage),
    );
    put(
      'isCharging',
      SharingCategory.charging,
      _isCharging(battery?.chargingState),
    );
    put(
      'chargingStartedAt',
      SharingCategory.charging,
      _pastTimestamp(battery?.chargingStartedAt),
    );
    put(
      'chargingDurationSeconds',
      SharingCategory.charging,
      _durationSeconds(battery?.chargingDuration),
    );

    put('networkState', SharingCategory.network, _networkStatus(snapshot.network?.status));

    final activity = snapshot.activity;
    put(
      'screenState',
      SharingCategory.activityIndicators,
      _screenState(activity?.screenState),
    );
    put(
      'activityState',
      SharingCategory.activityIndicators,
      _activityStatus(activity?.activityStatus),
    );
    put(
      'lastActivityAt',
      SharingCategory.activityIndicators,
      _pastTimestamp(activity?.lastObservedActivityAt),
    );

    // Ungated fields: they describe this device's own confidence, not a
    // category of personal information, so they are published whenever known.
    final availability = snapshot.availability;
    if (availability != null) {
      fields['availabilityState'] = availability.availability.name;
      fields['observedAt'] =
          availability.observedAt ?? _newestObservedAt(fields) ?? snapshot.collectedAt;
      final confirmed = availability.lastConfirmedAvailableAt;
      if (confirmed != null) fields['lastOnlineAt'] = confirmed.toUtc();
    } else {
      fields['observedAt'] =
          _newestObservedAt(fields) ?? snapshot.collectedAt.toUtc();
    }

    final deviceId = snapshot.deviceId;
    if (deviceId.isNotEmpty) fields['deviceId'] = deviceId;

    return SyncPayload(
      kind: SyncDocumentKind.deviceState,
      fields: fields,
      clearedFields: cleared,
      observedAt: _asDateTime(fields['observedAt']),
      shareable: true,
    );
  }

  /// Sanitizes the location document.
  ///
  /// The location document is all-or-nothing: if the `location` category is off
  /// the whole document is removed, so previously published coordinates do not
  /// linger (Phase 11 §34).
  SyncPayload sanitizeLocation({
    required DeviceStateSnapshot snapshot,
    required String ownerUserId,
    required Set<SharingCategory> sharedCategories,
    required bool sharingPaused,
    required int stateVersion,
  }) {
    final location = snapshot.location;
    if (location == null) {
      // Nothing has ever been observed, so there is no document of ours to
      // retract and nothing to publish.
      return const SyncPayload.withheld(kind: SyncDocumentKind.location);
    }
    if (sharingPaused ||
        !sharedCategories.contains(SharingCategory.location)) {
      return const SyncPayload.retracted(kind: SyncDocumentKind.location);
    }

    // A `stale` fix is still a real observation: it is published with its own
    // timestamp so the partner can see how old it is rather than a value that
    // silently claims to be current (Phase 10 §9, Phase 11 §10).
    final fix = location.location;
    final value = fix.value;
    if (value == null || !value.coordinate.isValid) {
      // Sharing is on but this device currently has no usable fix. Keeping the
      // previous document is truthful; inventing or deleting coordinates is not.
      return const SyncPayload.withheld(kind: SyncDocumentKind.location);
    }

    final fields = <String, Object?>{
      'ownerUserId': ownerUserId,
      'schemaVersion': schemaVersion,
      'stateVersion': stateVersion,
      'latitude': value.coordinate.latitude,
      'longitude': value.coordinate.longitude,
      'approximate': value.approximate,
      'observedAt': value.observedAt.toUtc(),
    };
    final cleared = <String>{};

    // Accuracy is optional, so a fix without one must actively remove a value
    // written earlier rather than leave a stale accuracy attached to a new fix.
    final accuracy = value.accuracyMeters;
    if (accuracy != null && accuracy.isFinite && accuracy >= 0) {
      fields['accuracyMeters'] = accuracy;
    } else {
      cleared.add('accuracyMeters');
    }

    final deviceId = snapshot.deviceId;
    if (deviceId.isNotEmpty) fields['deviceId'] = deviceId;

    // Distance and presence are gated separately from the coordinates, so
    // withdrawing them must remove the fields, not just stop updating them.
    final distance = location.distanceFromHome;
    final distanceUsable =
        sharedCategories.contains(SharingCategory.distanceFromHome) &&
        distance.availability == CapabilityAvailability.available;
    final metersToHome = distanceUsable ? distance.value : null;
    if (metersToHome != null && metersToHome.isFinite && metersToHome >= 0) {
      fields['distanceFromHomeKm'] = metersToHome / 1000;
      fields['homePresence'] = location.presence.name;
    } else {
      cleared.add('distanceFromHomeKm');
      cleared.add('homePresence');
    }

    return SyncPayload(
      kind: SyncDocumentKind.location,
      fields: fields,
      clearedFields: cleared,
      observedAt: value.observedAt.toUtc(),
      shareable: true,
    );
  }

  // ------------------------------------------------------------- validators --

  static int? _percentage(StateObservation<int>? observation) {
    if (observation == null ||
        observation.availability != CapabilityAvailability.available) {
      return null;
    }
    final value = observation.value;
    if (value == null || value < 0 || value > 100) return null;
    return value;
  }

  /// An unknown charging state is *not* published as `false`.
  static bool? _isCharging(StateObservation<BatteryChargingState>? observation) {
    if (observation == null ||
        observation.availability != CapabilityAvailability.available) {
      return null;
    }
    return switch (observation.value) {
      BatteryChargingState.charging || BatteryChargingState.full => true,
      BatteryChargingState.discharging ||
      BatteryChargingState.notCharging => false,
      _ => null,
    };
  }

  static int? _durationSeconds(StateObservation<Duration>? observation) {
    if (observation == null ||
        observation.availability != CapabilityAvailability.available) {
      return null;
    }
    final value = observation.value;
    if (value == null || value.isNegative) return null;
    return value.inSeconds;
  }

  static String? _networkStatus(StateObservation<NetworkOnlineStatus>? observation) {
    if (observation == null ||
        observation.availability != CapabilityAvailability.available) {
      return null;
    }
    final value = observation.value;
    if (value == null || value == NetworkOnlineStatus.unknown) return null;
    return value.name;
  }

  /// Publishes the display state, or the exact reason it is not available.
  static String? _screenState(StateObservation<DeviceScreenState>? observation) {
    if (observation == null) return null;
    if (observation.availability == CapabilityAvailability.available &&
        observation.value != null &&
        observation.value != DeviceScreenState.unknown) {
      return observation.value!.name;
    }
    return _availabilityMarker(observation.availability);
  }

  /// Publishes the activity signal state, or the exact reason it is missing.
  static String? _activityStatus(StateObservation<ActivityStatus>? observation) {
    if (observation == null) return null;
    if (observation.availability == CapabilityAvailability.available &&
        observation.value != null &&
        observation.value != ActivityStatus.unknown) {
      return observation.value!.name;
    }
    return _availabilityMarker(observation.availability);
  }

  /// A non-value availability that must survive synchronization unchanged.
  static String? _availabilityMarker(CapabilityAvailability availability) =>
      switch (availability) {
        CapabilityAvailability.available => null,
        CapabilityAvailability.unknown => null,
        _ => availability.name,
      };

  /// Only timestamps in the past are published: a device clock that is ahead
  /// must not create a future "last activity" the partner would read as now.
  DateTime? _pastTimestamp(DateTime? value) {
    if (value == null) return null;
    final utc = value.toUtc();
    if (utc.isAfter(now().toUtc())) return null;
    return utc;
  }

  static DateTime? _newestObservedAt(Map<String, Object?> fields) {
    DateTime? newest;
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value is! DateTime) continue;
      if (newest == null || value.isAfter(newest)) newest = value;
    }
    return newest;
  }

  static DateTime? _asDateTime(Object? value) =>
      value is DateTime ? value.toUtc() : null;
}
