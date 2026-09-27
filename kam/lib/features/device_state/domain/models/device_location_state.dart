import '../../../../core/freshness/data_freshness.dart';
import '../../../location/domain/models/location_state.dart';
import 'state_observation.dart';

/// Whether the operating system's location service is switched on.
///
/// Kept separate from the app's permission: a granted permission with the
/// service off is `serviceDisabled`, not `permissionDenied` (Phase 10 §4).
enum LocationServiceState { enabled, disabled, unknown }

/// One geographic fix, with everything needed to tell the truth about it.
class LocationFix {
  const LocationFix({
    required this.coordinate,
    required this.observedAt,
    this.accuracyMeters,
    this.approximate = false,
    this.source,
  });

  /// Where the device was at [observedAt].
  final Coordinate coordinate;

  /// When the *platform* took the fix, in UTC.
  ///
  /// This is never re-stamped: restoring a stored fix keeps its original time,
  /// so an old fix stays old (Phase 10 §10, §27).
  final DateTime observedAt;

  /// Platform-reported horizontal accuracy in metres, `null` when the platform
  /// did not report one. Never estimated or improved by this application.
  final double? accuracyMeters;

  /// Whether the OS is only providing reduced/approximate location because the
  /// user chose that grant (Android 12+ / iOS 14+). The application must not
  /// present such a fix as precise.
  final bool approximate;

  /// Technical producer, for example `android.location_manager`.
  final String? source;

  Map<String, Object?> toJson() => {
    'latitude': coordinate.latitude,
    'longitude': coordinate.longitude,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'accuracyMeters': accuracyMeters,
    'approximate': approximate,
    'source': source,
  };

  factory LocationFix.fromJson(Map<String, Object?> json) => LocationFix(
    coordinate: Coordinate(
      latitude: (json['latitude']! as num).toDouble(),
      longitude: (json['longitude']! as num).toDouble(),
    ),
    observedAt: DateTime.parse(json['observedAt']! as String).toUtc(),
    accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
    approximate: json['approximate'] == true,
    source: json['source'] as String?,
  );

  @override
  String toString() => 'LocationFix(observedAt: $observedAt, '
      'accuracy: $accuracyMeters, approximate: $approximate)';
}

/// The normalized location state of this device (Phase 10).
///
/// [location] is the most recent fix with its usability attached (`available`
/// while it is current enough, `stale` once it is not). [lastKnownLocation]
/// keeps the same fix as explicitly historical data, so a stale fix can never
/// be mistaken for a current position.
///
/// Home coordinates are deliberately absent: only the derived
/// [distanceFromHome] and [presence] leave this layer, so the exact home
/// position cannot leak through the snapshot.
class DeviceLocationState {
  const DeviceLocationState({
    required this.location,
    required this.lastKnownLocation,
    required this.permission,
    required this.serviceState,
    required this.distanceFromHome,
    required this.presence,
    this.homeConfigured = false,
    this.homeEnabled = false,
    this.homeRadiusMeters,
  });

  /// Nothing has been observed and nothing is known about permissions.
  static const DeviceLocationState unknown = DeviceLocationState(
    location: StateObservation<LocationFix>(
      availability: CapabilityAvailability.unknown,
    ),
    lastKnownLocation: StateObservation<LocationFix>(
      availability: CapabilityAvailability.unknown,
    ),
    permission: StateObservation<DevicePermissionState>(
      availability: CapabilityAvailability.unknown,
    ),
    serviceState: LocationServiceState.unknown,
    distanceFromHome: StateObservation<double>(
      availability: CapabilityAvailability.unknown,
    ),
    presence: HomePresence.unknown,
  );

  /// Most recent fix, classifiable as current or explicitly stale.
  final StateObservation<LocationFix> location;

  /// The same fix labelled as history; carries its original timestamp.
  final StateObservation<LocationFix> lastKnownLocation;

  /// Normalized OS permission for location.
  final StateObservation<DevicePermissionState> permission;

  /// Whether the OS location service is on.
  final LocationServiceState serviceState;

  /// Distance from the user's home in metres, derived and therefore
  /// accuracy-limited. `null` value whenever distance cannot be computed.
  final StateObservation<double> distanceFromHome;

  /// At-home / away / stale / unsupported / unknown classification.
  final HomePresence presence;

  /// Whether the user has configured a home location at all.
  final bool homeConfigured;

  /// Whether the configured home location is currently switched on.
  final bool homeEnabled;

  /// Radius of the configured home area in metres, when a home exists.
  final double? homeRadiusMeters;

  /// Every component observation, used for availability derivation.
  Iterable<StateObservation<Object?>> get observations => [
    location,
    lastKnownLocation,
    distanceFromHome,
  ];

  /// Freshness of the location picture at [now].
  ///
  /// The picture is as current as the newest fix it holds: the current read
  /// decides when it has a timestamp, and otherwise the retained history does.
  /// When the current read is blocked (denied, unsupported, no fix at all)
  /// there is no timestamp to classify and the answer is `unknown`.
  DataFreshness freshnessAt(DateTime now) {
    if (location.availability == CapabilityAvailability.stale) {
      return DataFreshness.stale;
    }
    if (location.observedAt != null) return location.freshnessAt(now);
    return lastKnownLocation.freshnessAt(now);
  }

  Map<String, Object?> toJson() => {
    'location': location.toJson(encodeValue: (fix) => fix.toJson()),
    'lastKnownLocation': lastKnownLocation.toJson(
      encodeValue: (fix) => fix.toJson(),
    ),
    'permission': permission.toJson(encodeValue: (state) => state.name),
    'serviceState': serviceState.name,
    'distanceFromHome': distanceFromHome.toJson(),
    'presence': presence.name,
    'homeConfigured': homeConfigured,
    'homeEnabled': homeEnabled,
    'homeRadiusMeters': homeRadiusMeters,
  };

  factory DeviceLocationState.fromJson(Map<String, Object?> json) =>
      DeviceLocationState(
        location: StateObservation<LocationFix>.fromJson(
          Map<String, Object?>.from(json['location']! as Map),
          decodeValue: (value) =>
              LocationFix.fromJson(Map<String, Object?>.from(value! as Map)),
        ),
        lastKnownLocation: StateObservation<LocationFix>.fromJson(
          Map<String, Object?>.from(json['lastKnownLocation']! as Map),
          decodeValue: (value) =>
              LocationFix.fromJson(Map<String, Object?>.from(value! as Map)),
        ),
        permission: StateObservation<DevicePermissionState>.fromJson(
          Map<String, Object?>.from(json['permission']! as Map),
          decodeValue: (value) =>
              DevicePermissionState.values.byName(value! as String),
        ),
        serviceState: LocationServiceState.values.byName(
          json['serviceState']! as String,
        ),
        distanceFromHome: StateObservation<double>.fromJson(
          Map<String, Object?>.from(json['distanceFromHome']! as Map),
          decodeValue: (value) => (value! as num).toDouble(),
        ),
        presence: HomePresence.values.byName(json['presence']! as String),
        homeConfigured: json['homeConfigured'] == true,
        homeEnabled: json['homeEnabled'] == true,
        homeRadiusMeters: (json['homeRadiusMeters'] as num?)?.toDouble(),
      );

  @override
  String toString() =>
      'DeviceLocationState(presence: ${presence.name}, '
      'location: ${location.availability.name}, '
      'service: ${serviceState.name})';
}
