import '../models/location_state.dart';
import 'geo_distance.dart';

/// A distance and at-home/away classification for one location fix.
class HomeDistanceResult {
  const HomeDistanceResult({
    required this.distanceMeters,
    required this.radiusMeters,
    required this.presence,
    this.accuracyMeters,
  });

  /// Great-circle distance from the home centre, in metres.
  ///
  /// Inherits the fix's uncertainty: it must always be shown together with
  /// [accuracyMeters] and never as an exact measurement.
  final double? distanceMeters;

  /// The configured home radius used for the classification.
  final double radiusMeters;

  /// Either [HomePresence.atHome] or [HomePresence.awayFromHome]; the caller
  /// decides `unknown`/`stale`/`unsupported` before reaching the geometry.
  final HomePresence presence;

  /// Horizontal accuracy of the fix in metres, when the platform reported one.
  final double? accuracyMeters;
}

/// Pure geometry for the at-home / away classification (Phase 10 §17–§20).
///
/// Only two inputs matter here: the fix and the user's configured home. The
/// calculator never infers a home, never smooths a distance, and never decides
/// freshness — that policy lives in the collector.
class HomePresenceCalculator {
  const HomePresenceCalculator();

  /// Classifies [fix] against [home].
  ///
  /// Returns `null` when the home coordinate or the fix is not a valid
  /// coordinate, so the caller reports `unknown` instead of a fabricated
  /// comparison.
  HomeDistanceResult? classify({
    required HomeLocation home,
    required Coordinate fix,
    double? accuracyMeters,
  }) {
    final distance = const GeoDistance().metersBetween(home.coordinate, fix);
    if (distance == null) return null;
    final radiusMeters = home.radiusMeters;
    return HomeDistanceResult(
      distanceMeters: distance,
      radiusMeters: radiusMeters,
      // Exactly on the boundary counts as at home: the radius is "within",
      // not "strictly less than".
      presence: distance <= radiusMeters
          ? HomePresence.atHome
          : HomePresence.awayFromHome,
      accuracyMeters: accuracyMeters,
    );
  }
}
