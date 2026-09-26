import 'package:flutter/services.dart';

import '../../domain/sources/network_platform_source.dart';

class MethodChannelNetworkGateway implements NetworkPlatformGateway {
  MethodChannelNetworkGateway(this.platformName);

  static const _methodChannel = MethodChannel('kam/device_network');
  static const _eventChannel = EventChannel('kam/device_network/events');

  @override
  final String platformName;

  @override
  Future<Object?> readCurrent() =>
      _methodChannel.invokeMethod<Object?>('getCurrentNetworkState');

  @override
  Stream<Object?> watchChanges() => _eventChannel.receiveBroadcastStream();
}
