import '../models/device_state_snapshot.dart';
import '../../../../core/domain/device_metric.dart';

/// Platform boundary for one capability collector. Native APIs stay behind
/// this interface; each collector can fail independently.
abstract interface class PlatformDeviceStateAdapter {
  String get platformName;
  DeviceCapabilityStatus capabilityStatus(DeviceMetric capability);
  Future<StateObservation<Object?>> collect(DeviceMetric capability);
}
