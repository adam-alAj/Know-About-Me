import 'dart:math' as math;

import '../models/location_state.dart';

/// Great-circle distance between two coordinates.
///
/// Uses the Haversine formula on a spherical earth (mean radius 6 371.0088 km).
/// Plain latitude/longitude subtraction would be wrong at every latitude
/// except the equator, so it is never used (Phase 10 §18).
///
/// The result inherits the uncertainty of its inputs: it is only as precise as
/// the underlying fix's `accuracyMeters`, which callers must keep alongside the
/// distance rather than presenting it as an exact measurement (§19).
class GeoDistance {
  const GeoDistance();

  /// Mean earth radius in metres (IUGG mean radius).
  static const double earthRadiusMeters = 6371008.8;

  /// Distance in metres between [from] and [to].
  ///
  /// Returns `null` when either coordinate is not a valid WGS-84 coordinate,
  /// rather than guessing a position for it.
  double? metersBetween(Coordinate from, Coordinate to) {
    if (!from.isValid || !to.isValid) return null;
    final lat1 = _radians(from.latitude);
    final lat2 = _radians(to.latitude);
    final deltaLat = _radians(to.latitude - from.latitude);
    final deltaLon = _radians(to.longitude - from.longitude);
    final sinHalfLat = math.sin(deltaLat / 2);
    final sinHalfLon = math.sin(deltaLon / 2);
    final h =
        sinHalfLat * sinHalfLat +
        math.cos(lat1) * math.cos(lat2) * sinHalfLon * sinHalfLon;
    final clamped = h.clamp(0.0, 1.0);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(clamped));
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;
}
