import '../../../../core/platform/device_platform.dart';
import '../../../../core/domain/device_metric.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/sources/platform_device_state_adapter.dart';

/// Honest Phase 6 adapter: native metric collectors are deferred to phases
/// 7–10. It declares no support and does not manufacture readings.
class UnavailablePlatformDeviceStateAdapter implements PlatformDeviceStateAdapter {
  const UnavailablePlatformDeviceStateAdapter(this.platform);
  final DevicePlatform platform;

  @override
  String get platformName => platform.name;

  @override
  DeviceCapabilityStatus capabilityStatus(DeviceMetric capability) =>
      const DeviceCapabilityStatus(CapabilitySupport.unsupported);

  @override
  Future<StateObservation<Object?>> collect(DeviceMetric capability) async =>
      StateObservation<Object?>(
        availability: CapabilityAvailability.unsupported,
        source: 'platform_adapter',
        platform: platformName,
      );
}
