import '../../../core/domain/device_metric.dart';
import '../../location/domain/models/location_state.dart';
import '../../device_state/domain/models/activity_state.dart';
import '../../device_state/domain/models/battery_state.dart';
import '../../device_state/domain/models/device_availability_evidence.dart';
import '../../device_state/domain/models/device_location_state.dart';
import '../../device_state/domain/models/device_state_snapshot.dart';
import '../../device_state/domain/models/network_state.dart';
import '../../device_state/domain/models/remote_device_state.dart';

/// Turns an authorized partner's synchronized state into the normalized
/// snapshot the Phase 13 Rule Engine evaluates (Phase 15, STEP 2 and STEP 23).
///
/// This is the **only** place where partner wire state becomes evaluation
/// input, so "what the engine is allowed to see" is one reviewable function
/// instead of a mapping spread across widgets.
///
/// The mapping is deliberately lossy in one direction only: it may refuse to
/// carry a value, and it may never invent one.
///
/// * A metric the partner did not publish becomes `unavailable`/`unknown`, so a
///   rule that needs it reports "cannot tell" rather than "not satisfied"
///   (STEP 13, STEP 29).
/// * An observation that claims availability but carries no usable value is
///   downgraded to `unknown`; it is never filled with a default.
/// * A non-available partner reason (`unsupported`, `permissionDenied`,
///   `serviceDisabled`, `error`, `stale`) survives unchanged, so the partner's
///   own truthfulness is preserved end to end.
/// * Only *observations* cross this boundary. No interpretation, no inference
///   and no behavioural claim is produced here (STEP 5, STEP 30).
///
/// Nothing is read from Firestore here: the caller supplies state that was
/// already obtained through the authorized Phase 11 stream (STEP 24).
abstract final class PartnerStateAdapter {
  /// The provenance recorded on values derived by this adapter rather than
  /// published verbatim by the partner device.
  static const String derivedSource = 'partner_sync_derived';

  /// The provenance recorded on values carried across unchanged.
  static const String carriedSource = 'partner_sync';

  /// Builds the snapshot the engine evaluates.
  ///
  /// [RemoteDeviceState] is treated as read-only input; the returned snapshot
  /// is a new value and shares nothing mutable with it.
  static DeviceStateSnapshot adapt(RemoteDeviceState state) {
    final collectedAt = state.observedAt ?? state.receivedAt;
    final location = state.location;

    return DeviceStateSnapshot(
      deviceId: state.deviceId ?? 'partner-device',
      userId: state.ownerUserId,
      collectedAt: collectedAt,
      capabilities: const <DeviceMetric, StateObservation<Object?>>{},
      battery: _battery(state, collectedAt),
      network: _network(state, collectedAt),
      activity: _activity(state, collectedAt),
      location: location == null ? null : _location(location),
      availability: _availability(state, collectedAt),
    );
  }

  // --------------------------------------------------------------- battery --

  static BatteryState _battery(RemoteDeviceState state, DateTime collectedAt) =>
      BatteryState(
    percentage: _percentage(state, collectedAt),
    chargingState: _chargingState(state, collectedAt),
    chargingDuration: _chargingDuration(state, collectedAt),
    // Charger type is not part of the synchronized contract, so it stays
    // explicitly unsupported rather than defaulting to a plausible charger.
    chargingSource: StateObservation<BatteryChargingSource>(
      availability: CapabilityAvailability.unsupported,
      source: carriedSource,
    ),
    chargingStartedAt: state.chargingStartedAt,
  );

  static StateObservation<int> _percentage(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.batteryPercentage];
    final value = observation?.value;
    if (observation == null ||
        observation.availability != CapabilityAvailability.available ||
        value is! int ||
        value < 0 ||
        value > 100) {
      return StateObservation<int>(
        availability: observation == null
            ? CapabilityAvailability.unavailable
            : _usableAvailability(observation.availability),
        observedAt: _carriedObservedAt(observation, collectedAt),
        source: carriedSource,
      );
    }
    return StateObservation<int>(
      availability: CapabilityAvailability.available,
      value: value,
      observedAt: _carriedObservedAt(observation, collectedAt),
      source: carriedSource,
    );
  }

  /// When a carried value was observed: the partner's own stamp when the wire
  /// format has one, and otherwise the document's observation time.
  ///
  /// The fallback matters for the enum-shaped fields, whose parser leaves the
  /// timestamp unset. Without it the engine would see "no observation
  /// timestamp" and report *unknown* rather than using a value the partner
  /// plainly published.
  static DateTime _carriedObservedAt(
    StateObservation<Object?>? observation,
    DateTime collectedAt,
  ) => observation?.observedAt ?? collectedAt;

  static StateObservation<BatteryChargingState> _chargingState(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.chargingState];
    final decoded = _chargingStates[observation?.value];
    if (observation == null ||
        observation.availability != CapabilityAvailability.available ||
        decoded == null) {
      return StateObservation<BatteryChargingState>(
        availability: observation == null
            ? CapabilityAvailability.unavailable
            : _usableAvailability(observation.availability),
        observedAt: _carriedObservedAt(observation, collectedAt),
        source: carriedSource,
      );
    }
    return StateObservation<BatteryChargingState>(
      availability: CapabilityAvailability.available,
      // Normalized to the canonical names the rule catalogue offers, so a
      // partner's `discharging` matches a rule written as "Not charging".
      value: decoded,
      observedAt: _carriedObservedAt(observation, collectedAt),
      source: carriedSource,
    );
  }

  static const Map<Object?, BatteryChargingState> _chargingStates = {
    'charging': BatteryChargingState.charging,
    'full': BatteryChargingState.full,
    'fullyCharged': BatteryChargingState.full,
    'discharging': BatteryChargingState.notCharging,
    'notCharging': BatteryChargingState.notCharging,
  };

  /// The charging duration the partner reported, stamped with the time the
  /// partner reported it.
  ///
  /// The wire format timestamps this value with the charging *session start*
  /// (`chargingStartedAt`), and that is not an observation time: stamping it
  /// here would make every long charging session look stale to the engine's
  /// freshness policy, so a "charging for four hours" rule could never fire.
  /// The session start is still preserved on
  /// `BatteryState.chargingStartedAt`, which is where the time-threshold planner
  /// reads it from, and the fact text itself carries the duration.
  static StateObservation<Duration> _chargingDuration(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.chargingDuration];
    final value = observation?.value;
    if (observation == null ||
        observation.availability != CapabilityAvailability.available ||
        value is! Duration ||
        value.isNegative) {
      return StateObservation<Duration>(
        availability: observation == null
            ? CapabilityAvailability.unavailable
            : _usableAvailability(observation.availability),
        observedAt: collectedAt,
        source: carriedSource,
      );
    }
    return StateObservation<Duration>(
      availability: CapabilityAvailability.available,
      value: value,
      observedAt: collectedAt,
      source: carriedSource,
    );
  }

  // --------------------------------------------------------------- network --

  static NetworkState _network(RemoteDeviceState state, DateTime collectedAt) =>
      NetworkState(
        // The synchronized contract carries reachability, not the transport or
        // the Internet probe, so both stay explicitly unknown.
        connectivity: StateObservation<ConnectivityType>(
          availability: CapabilityAvailability.unknown,
          source: carriedSource,
        ),
        internet: StateObservation<InternetReachability>(
          availability: CapabilityAvailability.unknown,
          source: carriedSource,
        ),
        status: _networkStatus(state, collectedAt),
        offlineDuration: _offlineDuration(state, collectedAt),
        lastOnlineAt: state.lastOnlineAt,
        offlineStartedAt: null,
      );

  static StateObservation<NetworkOnlineStatus> _networkStatus(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.networkStatus];
    final decoded = _onlineStatuses[observation?.value];
    if (observation == null ||
        observation.availability != CapabilityAvailability.available ||
        decoded == null) {
      return StateObservation<NetworkOnlineStatus>(
        availability: observation == null
            ? CapabilityAvailability.unavailable
            : _usableAvailability(observation.availability),
        observedAt: _carriedObservedAt(observation, collectedAt),
        source: carriedSource,
      );
    }
    return StateObservation<NetworkOnlineStatus>(
      availability: CapabilityAvailability.available,
      value: decoded,
      observedAt: _carriedObservedAt(observation, collectedAt),
      source: carriedSource,
    );
  }

  static const Map<Object?, NetworkOnlineStatus> _onlineStatuses = {
    'online': NetworkOnlineStatus.online,
    'offline': NetworkOnlineStatus.offline,
  };

  /// How long the partner had been offline **as of the last state the partner
  /// published**.
  ///
  /// The synchronized contract does not carry an offline duration, so it is
  /// derived from the partner's own last-confirmed-online time. Two deliberate
  /// limits keep this honest:
  ///
  /// * the value is measured up to the document's observation time, never up to
  ///   *now*, because a duration we extend ourselves would be our inference and
  ///   not the partner's evidence;
  /// * the timestamp carried with it is the document's observation time, so the
  ///   engine's freshness policy (which the rule may opt out of) governs whether
  ///   it is still current. A rule built on an old document reports "stale" or
  ///   "cannot tell" rather than confidently reporting a duration (STEP 14).
  static StateObservation<Duration> _offlineDuration(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final status = state.observations[DeviceMetric.networkStatus];
    final lastOnlineAt = state.lastOnlineAt;
    if (status?.value != 'offline' || lastOnlineAt == null) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unavailable,
        observedAt: status?.observedAt,
        source: carriedSource,
      );
    }
    final elapsed = collectedAt.toUtc().difference(lastOnlineAt.toUtc());
    if (elapsed.isNegative) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
        observedAt: collectedAt,
        source: derivedSource,
      );
    }
    return StateObservation<Duration>(
      availability: CapabilityAvailability.available,
      value: elapsed,
      observedAt: collectedAt,
      source: derivedSource,
    );
  }

  // -------------------------------------------------------------- activity --

  static ActivityState _activity(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) => ActivityState(
    screenState: _screenState(state, collectedAt),
    activityStatus: _activityStatus(state, collectedAt),
    // Our own lifecycle is not the partner's, so it is never attributed to them.
    appLifecycle: StateObservation<AppLifecyclePhase>(
      availability: CapabilityAvailability.unknown,
      source: carriedSource,
    ),
    activityDuration: StateObservation<Duration>(
      availability: CapabilityAvailability.unknown,
      source: carriedSource,
    ),
    lastObservedActivityAt: state.lastActivityAt,
  );

  static StateObservation<DeviceScreenState> _screenState(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.screenState];
    final decoded = _screenStates[observation?.value];
    if (decoded == null) {
      return StateObservation<DeviceScreenState>(
        availability: observation == null
            ? CapabilityAvailability.unavailable
            : _usableAvailability(observation.availability),
        observedAt: _carriedObservedAt(observation, collectedAt),
        source: carriedSource,
      );
    }
    return StateObservation<DeviceScreenState>(
      availability: CapabilityAvailability.available,
      value: decoded,
      observedAt: _carriedObservedAt(observation, collectedAt),
      source: carriedSource,
    );
  }

  static const Map<Object?, DeviceScreenState> _screenStates = {
    'on': DeviceScreenState.on,
    'off': DeviceScreenState.off,
  };

  static StateObservation<ActivityStatus> _activityStatus(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.activityState];
    final decoded = _activityStatuses[observation?.value];
    if (decoded == null) {
      return StateObservation<ActivityStatus>(
        availability: observation == null
            ? CapabilityAvailability.unavailable
            : _usableAvailability(observation.availability),
        observedAt: _carriedObservedAt(observation, collectedAt),
        source: carriedSource,
      );
    }
    return StateObservation<ActivityStatus>(
      availability: CapabilityAvailability.available,
      value: decoded,
      observedAt: _carriedObservedAt(observation, collectedAt),
      source: carriedSource,
    );
  }

  static const Map<Object?, ActivityStatus> _activityStatuses = {
    'activityDetected': ActivityStatus.activityDetected,
    'noActivityObserved': ActivityStatus.noActivityObserved,
  };

  // -------------------------------------------------------------- location --

  static DeviceLocationState _location(RemoteLocationState location) {
    final observedAt = location.observedAt;
    final fix = location.hasCoordinates
        ? StateObservation<LocationFix>(
            availability: CapabilityAvailability.available,
            value: LocationFix(
              coordinate: Coordinate(
                latitude: location.latitude!,
                longitude: location.longitude!,
              ),
              // A fix keeps the partner's own observation time; it is never
              // re-stamped when we read it (Phase 10 §10).
              observedAt: observedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              accuracyMeters: location.accuracyMeters,
              approximate: location.approximate,
              source: carriedSource,
            ),
            observedAt: observedAt,
            source: carriedSource,
          )
        : StateObservation<LocationFix>(
            availability: _usableAvailability(location.availability),
            observedAt: observedAt,
            source: carriedSource,
          );

    final distanceKm = location.distanceFromHomeKm;
    final distance = distanceKm == null
        ? StateObservation<double>(
            availability: CapabilityAvailability.unavailable,
            observedAt: observedAt,
            source: carriedSource,
          )
        : StateObservation<double>(
            availability: CapabilityAvailability.available,
            // The engine's normalized contract is metres; the wire carries km.
            value: distanceKm * 1000,
            observedAt: observedAt,
            source: carriedSource,
          );

    final hasDistance = distanceKm != null;

    return DeviceLocationState(
      location: fix,
      // The same fix as explicit history, so a rule can ask about an age
      // without a stale fix ever being presented as the current position.
      lastKnownLocation: location.hasCoordinates
          ? StateObservation<LocationFix>(
              availability: CapabilityAvailability.available,
              value: fix.value,
              observedAt: observedAt,
              source: carriedSource,
            )
          : StateObservation<LocationFix>(
              availability: _usableAvailability(location.availability),
              observedAt: observedAt,
              source: carriedSource,
            ),
      // The partner's permission and OS service state are not synchronized;
      // claiming either would be inventing state about their device.
      permission: StateObservation<DevicePermissionState>(
        availability: CapabilityAvailability.unknown,
        source: carriedSource,
      ),
      serviceState: LocationServiceState.unknown,
      distanceFromHome: distance,
      presence: location.presence ?? HomePresence.unknown,
      homeConfigured: hasDistance,
      homeEnabled: hasDistance,
      homeRadiusMeters: null,
    );
  }

  // ---------------------------------------------------------- availability --

  static DeviceAvailabilityEvidence _availability(
    RemoteDeviceState state,
    DateTime collectedAt,
  ) {
    final observation = state.observations[DeviceMetric.deviceAvailability];
    final availability = _availabilities[observation?.value];
    if (availability == null) {
      return DeviceAvailabilityEvidence(
        availability: observation == null
            ? CapabilityAvailability.unknown
            : _usableAvailability(observation.availability),
        observedAt: collectedAt,
        source: carriedSource,
      );
    }
    return DeviceAvailabilityEvidence(
      availability: availability,
      // The partner's last confirmed usable connectivity is the only positive
      // evidence the contract carries. It is never re-stamped to "now", so the
      // engine's freshness policy still sees an old confirmation as old.
      lastConfirmedAvailableAt: state.lastOnlineAt,
      observedAt: _carriedObservedAt(observation, collectedAt),
      source: carriedSource,
    );
  }

  static const Map<Object?, CapabilityAvailability> _availabilities = {
    'available': CapabilityAvailability.available,
    'stale': CapabilityAvailability.stale,
    'unavailable': CapabilityAvailability.unavailable,
    'unknown': CapabilityAvailability.unknown,
    'unsupported': CapabilityAvailability.unsupported,
    'permissionDenied': CapabilityAvailability.permissionDenied,
    'serviceDisabled': CapabilityAvailability.serviceDisabled,
    'error': CapabilityAvailability.error,
  };

  /// An observation that claims availability but yields no usable value is not
  /// `available`; the honest answer is `unknown`.
  static CapabilityAvailability _usableAvailability(
    CapabilityAvailability availability,
  ) => availability == CapabilityAvailability.available
      ? CapabilityAvailability.unknown
      : availability;
}
