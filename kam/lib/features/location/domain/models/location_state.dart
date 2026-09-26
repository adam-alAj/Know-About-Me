import '../../../device_state/domain/models/metric_value.dart';

/// A geographic coordinate.
///
/// Deliberately framework-neutral: the domain layer must not depend on a
/// Firebase or mapping package type.
class Coordinate {
  const Coordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

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
class HomeLocation {
  const HomeLocation({
    required this.coordinate,
    this.label,
    this.radiusKm = 0.3,
  });

  /// Centre point of the home area.
  final Coordinate coordinate;

  /// User-defined place name, for example `Home`.
  final String? label;

  /// Radius used to classify the device as at / near home (FR-024).
  final double radiusKm;

  @override
  String toString() => 'HomeLocation(label: $label, radiusKm: $radiusKm)';
}

/// Basic presence classification derived from location (SRS FR-024).
enum HomePresence {
  atHome,
  nearHome,
  awayFromHome,

  /// Location is missing, stale beyond usefulness, or permission is absent.
  unknown,
}

/// The location-related observable state of a device.
///
/// Location is treated as more sensitive than other state (NFR-036), so
/// precision is never over-claimed: [accuracyMeters] is retained and stale
/// locations are exposed as stale via [coordinates]'s freshness (FR-020,
/// FR-025).
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
