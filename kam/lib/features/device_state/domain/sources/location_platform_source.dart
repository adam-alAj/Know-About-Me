/// Platform-neutral location source. Tests inject a fake instead of invoking
/// native channels or the OS permission dialog.
///
/// The gateway exposes exactly three operations, all user- or lifecycle-driven:
/// read the permission/service status, request the permission once when the
/// user asks, and read one location fix. Continuous throttled fixes arrive on
/// [watchChanges] only while a subscription is active.
abstract interface class LocationPlatformGateway {
  String get platformName;

  /// Current OS permission and service state. Never prompts.
  Future<Object?> readStatus();

  /// Asks the OS for permission. Only called from an explicit user action.
  Future<Object?> requestPermission();

  /// Requests one location fix.
  Future<Object?> readCurrentLocation();

  /// Throttled, platform-managed location updates while subscribed.
  Stream<Object?> watchChanges();
}

/// Raw permission/service response.
///
/// [permission] stays a platform string here so an unrecognized value can be
/// reported as `unknown` instead of being silently mapped to something else.
class LocationStatusSample {
  const LocationStatusSample({
    required this.supported,
    required this.permission,
    required this.precise,
    required this.serviceEnabled,
  });

  /// Whether the platform provides location at all.
  final bool supported;

  /// `granted`, `denied`, `permanentlyDenied`, `restricted`, `limited`,
  /// `notDetermined`, or `unknown`.
  final String? permission;

  /// Whether precise (not reduced/approximate) location is authorized.
  final bool precise;

  /// Whether the OS location service itself is switched on.
  final bool serviceEnabled;

  factory LocationStatusSample.fromPlatform(Object? value) {
    if (value is LocationStatusSample) return value;
    if (value is! Map) {
      throw const FormatException('Native location status was not a map.');
    }
    return LocationStatusSample(
      supported: value['supported'] != false,
      permission: value['permission'] as String?,
      precise: value['precise'] == true,
      serviceEnabled: value['serviceEnabled'] == true,
    );
  }
}

/// Raw location fix response. Values are untrusted: the collector validates
/// the coordinate range and rejects invalid fixes instead of clamping them.
class LocationFixSample {
  const LocationFixSample({
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.observedAt,
    this.approximate = false,
    this.error,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  /// Platform fix time in UTC, when the OS reported one.
  final DateTime? observedAt;

  /// Whether the OS supplied a reduced-accuracy fix.
  final bool approximate;

  /// Platform failure reason: `timeout`, `no_fix`, `disabled`, `denied`.
  final String? error;

  factory LocationFixSample.fromPlatform(Object? value) {
    if (value is LocationFixSample) return value;
    if (value is! Map) {
      throw const FormatException('Native location fix was not a map.');
    }
    final rawTime = value['observedAt'];
    return LocationFixSample(
      latitude: (value['latitude'] as num?)?.toDouble(),
      longitude: (value['longitude'] as num?)?.toDouble(),
      accuracyMeters: (value['accuracyMeters'] as num?)?.toDouble(),
      observedAt: rawTime is String ? DateTime.tryParse(rawTime)?.toUtc() : null,
      approximate: value['approximate'] == true,
      error: value['error'] as String?,
    );
  }
}
