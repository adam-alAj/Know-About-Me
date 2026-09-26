import 'package:flutter/services.dart';
import '../../domain/sources/battery_platform_source.dart';

class MethodChannelBatteryGateway implements BatteryPlatformGateway {
  MethodChannelBatteryGateway(this.platformName);

  static const _methodChannel = MethodChannel('kam/device_battery');
  static const _eventChannel = EventChannel('kam/device_battery/events');

  @override
  final String platformName;

  @override
  Future<Object?> readCurrent() => _methodChannel.invokeMethod<Object?>(
    'getCurrentBatteryState',
  );

  @override
  Stream<Object?> watchChanges() => _eventChannel.receiveBroadcastStream();
}
