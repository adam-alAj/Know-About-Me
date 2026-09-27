import 'package:flutter/services.dart';

import '../../domain/sources/location_platform_source.dart';

/// Native bridge for location status, one-shot fixes and throttled updates.
///
/// The Dart layer only ever calls [requestPermission] from an explicit user
/// action, and only subscribes to [watchChanges] while monitoring is active —
/// the native side is responsible for throttling (minimum time / minimum
/// distance), so no Dart timer polls for location.
class MethodChannelLocationGateway implements LocationPlatformGateway {
  MethodChannelLocationGateway(this.platformName);

  static const _methodChannel = MethodChannel('kam/device_location');
  static const _eventChannel = EventChannel('kam/device_location/events');

  @override
  final String platformName;

  @override
  Future<Object?> readStatus() =>
      _methodChannel.invokeMethod<Object?>('getLocationStatus');

  @override
  Future<Object?> requestPermission() =>
      _methodChannel.invokeMethod<Object?>('requestLocationPermission');

  @override
  Future<Object?> readCurrentLocation() =>
      _methodChannel.invokeMethod<Object?>('getCurrentLocation');

  @override
  Stream<Object?> watchChanges() => _eventChannel.receiveBroadcastStream();
}
