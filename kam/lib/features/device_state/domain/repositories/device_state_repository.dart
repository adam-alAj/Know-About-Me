import '../models/device_state_snapshot.dart';
import '../../../../core/domain/device_metric.dart';

/// Local state repository. Partner state has a separate type and read path.
abstract interface class DeviceStateRepository {
  Future<DeviceStateSnapshot> getCurrentLocalState();
  Stream<DeviceStateSnapshot> watchLocalState();
  Future<DeviceStateSnapshot> refresh();
  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus;
}

/// Explicit marker for data received from an authorized partner in a later
/// synchronization phase. It cannot be passed as local state accidentally.
class PartnerDeviceState {
  const PartnerDeviceState(this.snapshot);
  final DeviceStateSnapshot snapshot;
}
