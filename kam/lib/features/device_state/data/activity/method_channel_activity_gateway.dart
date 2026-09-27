import 'package:flutter/services.dart';

import '../../domain/sources/activity_platform_source.dart';

/// Native bridge for the Android display-state signal.
///
/// Only invoked on platforms whose collector declares screen support
/// (Android); iOS has no public screen on/off API, so no channel is ever
/// called there and no approximation is made.
class MethodChannelActivityGateway implements ActivityPlatformGateway {
  MethodChannelActivityGateway(this.platformName);

  static const _methodChannel = MethodChannel('kam/device_activity');
  static const _eventChannel = EventChannel('kam/device_activity/events');

  @override
  final String platformName;

  @override
  Future<Object?> readCurrent() =>
      _methodChannel.invokeMethod<Object?>('getCurrentActivityState');

  @override
  Stream<Object?> watchChanges() => _eventChannel.receiveBroadcastStream();
}
