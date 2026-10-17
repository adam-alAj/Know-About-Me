import 'package:flutter/services.dart';

/// Collects the non-sensitive Android metrics supported by periodic work.
/// Location is deliberately excluded: this bridge can run while the app is
/// backgrounded and the product only requests foreground location permission.
abstract final class KamBackgroundMonitoring {
  static const MethodChannel _channel = MethodChannel(
    'kam/background_device_state',
  );

  /// Returns only system-observed battery, network and interactive-display
  /// values with their collection time. Throws if the native plugin is absent.
  static Future<Map<String, Object?>> collectSupportedState() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'collectSupportedState',
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_background_state',
        message: 'The Android state collector returned no sample.',
      );
    }
    return result;
  }
}
