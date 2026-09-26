import '../../../../core/platform/device_platform.dart';

/// Identity and descriptive metadata for a device owned by a user.
///
/// A single user may eventually own more than one device, so device identity is
/// separate from user identity (SRS Task 9: `Device`).
class Device {
  const Device({
    required this.id,
    required this.ownerUserId,
    required this.platform,
    this.model,
    this.osVersion,
    this.appVersion,
    this.registeredAt,
  });

  /// Stable identifier for this device, generated at first launch.
  final String id;

  /// The user who owns and operates the device.
  final String ownerUserId;

  /// The operating system family.
  ///
  /// Defined in `core/platform/device_platform.dart` (moved there in Phase 2 so
  /// that `core/` does not depend on a feature).
  final DevicePlatform platform;

  /// Marketing model name where available, for example `Pixel 8`.
  final String? model;

  /// Operating-system version string where available.
  final String? osVersion;

  /// Version of this application installed on the device.
  final String? appVersion;

  /// When the device was first registered with the service, in UTC.
  final DateTime? registeredAt;

  @override
  String toString() =>
      'Device(id: $id, ownerUserId: $ownerUserId, platform: ${platform.name})';
}
