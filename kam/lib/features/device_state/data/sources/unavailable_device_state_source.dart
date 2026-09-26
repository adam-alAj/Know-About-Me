import '../../../../core/platform/device_platform.dart';
import '../../../../core/result/result.dart';
import '../../domain/models/device_capability.dart';
import '../../domain/models/device_state.dart';
import '../../domain/sources/device_state_source.dart';

/// Device-id used before the device is registered with the backend (Phase 4+).
const String kUnregisteredDeviceId = 'unregistered-device';

/// A [DeviceStateSource] that observes nothing.
///
/// Used until native collectors exist. It is deliberately *not* a fake: it
/// reports every capability as unsupported and returns an all-unknown
/// [DeviceState]. It never invents a battery percentage, charging state or
/// location (SRS constraint 4, FR-048, FR-068).
class UnavailableDeviceStateSource implements DeviceStateSource {
  const UnavailableDeviceStateSource({required this.platform});

  /// The platform this source runs on, used for capability reporting.
  final DevicePlatform platform;

  @override
  DeviceCapabilityReport get capabilities =>
      DeviceCapabilityReport.none(platform);

  @override
  Future<Result<DeviceState>> readCurrentState() async {
    return Success(DeviceState.empty(kUnregisteredDeviceId));
  }
}
