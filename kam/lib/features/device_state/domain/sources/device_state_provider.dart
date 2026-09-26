import '../models/device_state_snapshot.dart';
import '../../../../core/domain/device_metric.dart';

/// Local device observation contract used by repositories and application
/// state. Implementations make no promise of continuous background execution.
abstract interface class DeviceStateProvider {
  Future<DeviceStateSnapshot> getCurrentState();
  Stream<DeviceStateSnapshot> watchState();
  Map<DeviceMetric, DeviceCapabilityStatus> getCapabilityStatus();
}
