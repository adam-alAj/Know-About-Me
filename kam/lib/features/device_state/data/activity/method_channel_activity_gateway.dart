import 'package:flutter/services.dart';

import '../../domain/sources/activity_platform_source.dart';

/// Native bridge for the Android display-state signal. Non-Android targets
/// are reported unsupported by the collector and do not invoke this channel.
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
