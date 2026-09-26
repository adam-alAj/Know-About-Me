import 'package:flutter/foundation.dart';

import 'device_platform.dart';

/// Reports which platform the application is running on.
///
/// This is the **only** place that is allowed to read Flutter's
/// `defaultTargetPlatform`. Feature and domain code depend on this interface, so
/// platform detection stays behind a boundary (SRS constraint 3, NFR-019) and can
/// be replaced with a fake in tests.
abstract interface class PlatformInfo {
  /// The current platform.
  DevicePlatform get platform;
}

/// Convenience checks derived from the reported platform.
extension PlatformInfoChecks on PlatformInfo {
  /// Whether the app is running on Android.
  bool get isAndroid => platform == DevicePlatform.android;

  /// Whether the app is running on iOS.
  bool get isIos => platform == DevicePlatform.ios;
}

/// Production [PlatformInfo] backed by Flutter's target-platform detection.
class FlutterPlatformInfo implements PlatformInfo {
  const FlutterPlatformInfo();

  @override
  DevicePlatform get platform {
    if (kIsWeb) return DevicePlatform.unknown;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return DevicePlatform.android;
      case TargetPlatform.iOS:
        return DevicePlatform.ios;
      default:
        // Desktop platforms are not product targets; report unknown rather than
        // pretending they are a supported mobile platform.
        return DevicePlatform.unknown;
    }
  }
}
