import '../../../device_state/domain/models/metric_value.dart';

/// A geographic coordinate.
///
/// Deliberately framework-neutral: the domain layer must not depend on a
/// Firebase or mapping package type.
class Coordinate {
  const Coordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// Whether this is a usable WGS-84 coordinate.
  ///
  /// Guards against platform values that are NaN, infinite, or outside the
  /// valid ranges, so an invalid fix is rejected instead of being plotted
  /// somewhere plausible (Phase 10).
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  @override
  bool operator ==(Object other) =>
      other is Coordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'Coordinate(${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)})';
}

/// The user's configured home location (SRS FR-022).
///
/// Created explicitly by the user (profile settings, owner-only) — never
/// inferred from GPS history, frequent locations, Wi-Fi or IP address. The
/// partner never receives these coordinates: only the derived distance and
/// presence travel (FIRESTORE_DATA_MODEL §2, NFR-005, NFR-036).
class HomeLocation {
  const HomeLocation({
    required this.coordinate,
    this.label,
    this.radiusKm = 0.3,
    this.enabled = true,
  });

  /// Centre point of the home area.
  final Coordinate coordinate;

  /// User-defined place name, for example `Home`.
  final String? label;

  /// Radius used to classify the device as at / near home (FR-024).
  ///
  /// Defaults to 300 m, the value already used by the profile model.
  final double radiusKm;

  /// Whether home classification is currently switched on by the user.
  ///
  /// A disabled home location keeps its coordinates but must not produce
  /// at-home/away statements.
  final bool enabled;

  /// Radius in metres, so callers cannot accidentally compare km to m.
  double get radiusMeters => radiusKm * 1000;

  HomeLocation copyWith({
    Coordinate? coordinate,
    String? label,
    double? radiusKm,
    bool? enabled,
  }) {
    return HomeLocation(
      coordinate: coordinate ?? this.coordinate,
      label: label ?? this.label,
      radiusKm: radiusKm ?? this.radiusKm,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() =>
      'HomeLocation(label: $label, radiusKm: $radiusKm, enabled: $enabled)';
}

/// Basic presence classification derived from location (SRS FR-024).
///
/// [atHome] and [awayFromHome] are only produced from a location that is
/// usable *now*; [unknown], [stale] and [unsupported] must never be folded
/// into `awayFromHome` (Phase 10 §20).
enum HomePresence {
  atHome,

  /// Reserved for a future user-configured near-home band; the Phase 10
  /// derivation classifies strictly by the configured home radius.
  nearHome,

  awayFromHome,

  /// A location exists but is too old to classify presence with.
  stale,

  /// The platform cannot provide location at all.
  unsupported,

  /// Missing home, missing location, permission or service problems.
  unknown,
}

/// The location-related observable state of a device.
///
/// Location is treated as more sensitive than other state (NFR-036), so
/// precision is never over-claimed: [accuracyMeters] is retained and stale
/// locations are exposed as stale via [coordinates]'s freshness (FR-020,
/// FR-025).
///
/// This is the Phase 2/3 summary model used by the existing rule-engine
/// contract. Phase 10 adds the richer normalized observation model
/// (`DeviceLocationState` in the device-state feature) which carries
/// permission, service and current-vs-last-known semantics explicitly.
class LocationState {
  const LocationState({
    required this.coordinates,
    required this.distanceFromHomeKm,
    required this.presence,
    this.placeLabel,
    this.accuracyMeters,
  });

  /// An unknown location state; used whenever location is unavailable.
  factory LocationState.unknown({bool unsupported = false}) {
    return LocationState(
      coordinates: unsupported
          ? const MetricValue<Coordinate>.unsupported(source: 'location')
          : const MetricValue<Coordinate>.unknown(source: 'location'),
      distanceFromHomeKm: const MetricValue<double>.unknown(
        source: 'location.distance',
      ),
      presence: HomePresence.unknown,
    );
  }

  /// Last known coordinate with its own freshness metadata (FR-019).
  final MetricValue<Coordinate> coordinates;

  /// Approximate distance from home, marked as derived (FR-023).
  final MetricValue<double> distanceFromHomeKm;

  /// Presence classification; may be an interpretation if rule-driven.
  final HomePresence presence;

  /// Human-readable place name when resolvable, for example `Home`.
  final String? placeLabel;

  /// Reported horizontal accuracy in metres, when the platform provides it
  /// (FR-020). Retained so the app never presents an approximation as exact.
  final double? accuracyMeters;
}
