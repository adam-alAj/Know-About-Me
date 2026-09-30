/// Opens an authorized coordinate in the platform's map application.
///
/// This is an *action*, not an observation: it never reads or writes location
/// itself, and it never receives a coordinate the user is not already allowed to
/// see. The caller passes the partner's latest **authorized** fix; the platform
/// layer only turns it into a standard geographic URI.
///
/// Keeping it behind an interface lets the UI be tested without an Android
/// intent, exactly like the other platform gateways.
abstract interface class MapLauncher {
  /// The platform this launcher is running on.
  String get platformName;

  /// Whether a map application can plausibly handle a coordinate on this
  /// platform. `false` on targets with no map deep-link mechanism.
  bool get isSupported;

  /// Opens [latitude],[longitude] in an external map application.
  ///
  /// [label] is an optional place name shown as the map pin label and never
  /// includes the raw coordinate string. Returns `true` when an external
  /// application accepted the request, `false` when none could (the caller then
  /// tells the user rather than silently doing nothing).
  Future<bool> openCoordinates({
    required double latitude,
    required double longitude,
    String? label,
  });
}
