import 'package:flutter/services.dart';

import '../../domain/sources/map_launcher.dart';

/// Android implementation of [MapLauncher] over the `kam/map_launcher` channel.
///
/// The native side builds a `geo:` intent (falling back to an https Google Maps
/// link) and starts whatever map application the user has installed. Only the
/// authorized coordinate leaves the Dart side — no history, no trail.
class MethodChannelMapLauncher implements MapLauncher {
  MethodChannelMapLauncher(this.platformName);

  static const _methodChannel = MethodChannel('kam/map_launcher');

  @override
  final String platformName;

  @override
  bool get isSupported => platformName == 'android';

  @override
  Future<bool> openCoordinates({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    if (!isSupported) return false;
    try {
      final opened = await _methodChannel.invokeMethod<bool>('openCoordinates', {
        'latitude': latitude,
        'longitude': longitude,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      });
      return opened ?? false;
    } on PlatformException {
      // No map application could handle the request, or the platform refused
      // it. The caller surfaces an honest failure instead of pretending a map
      // opened.
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
