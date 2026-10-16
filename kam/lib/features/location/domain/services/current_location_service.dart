import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationResultSource { fresh, cached }

class CurrentLocationResult {
  const CurrentLocationResult({
    required this.position,
    required this.source,
  });

  final Position position;
  final LocationResultSource source;
}

enum LocationFetchFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  noUsableFix,
}

class LocationFetchException implements Exception {
  const LocationFetchException(this.reason);

  final LocationFetchFailure reason;

  @override
  String toString() => 'LocationFetchException($reason)';
}

/// Fetches a one-shot foreground location for the explicit map action.
///
/// Cached coordinates are accepted only when they are recent and accurate
/// enough for map centering. The result identifies cached fixes so callers can
/// tell the user that the position may not be live.
class CurrentLocationService {
  const CurrentLocationService();

  static const Duration _freshTimeout = Duration(seconds: 15);
  static const Duration _maxCacheAge = Duration(minutes: 2);
  static const double _maxAccuracyMeters = 150;

  Future<CurrentLocationResult> fetch() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationFetchException(
          LocationFetchFailure.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const LocationFetchException(
          LocationFetchFailure.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFetchException(
          LocationFetchFailure.permissionDeniedForever,
        );
      }

      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: _freshTimeout,
          ),
        ).timeout(_freshTimeout);

        if (_isUsable(fresh)) {
          return CurrentLocationResult(
            position: fresh,
            source: LocationResultSource.fresh,
          );
        }
      } on TimeoutException {
        // Continue to the bounded cache fallback.
      }

      final cached = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (cached != null && _isUsable(cached)) {
        return CurrentLocationResult(
          position: cached,
          source: LocationResultSource.cached,
        );
      }

      throw const LocationFetchException(LocationFetchFailure.noUsableFix);
    } on LocationFetchException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const LocationFetchException(LocationFetchFailure.serviceDisabled);
    } on PermissionDeniedException {
      throw const LocationFetchException(LocationFetchFailure.permissionDenied);
    } on TimeoutException {
      throw const LocationFetchException(LocationFetchFailure.noUsableFix);
    } catch (_) {
      // Avoid exposing platform exception details to users. Log them through
      // the app's diagnostics service if one is configured.
      throw const LocationFetchException(LocationFetchFailure.noUsableFix);
    }
  }

  bool _isUsable(Position position) {
    final now = DateTime.now();
    final age = now.difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude >= -90 &&
        position.latitude <= 90 &&
        position.longitude >= -180 &&
        position.longitude <= 180 &&
        !age.isNegative &&
        age <= _maxCacheAge &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= _maxAccuracyMeters;
  }

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
