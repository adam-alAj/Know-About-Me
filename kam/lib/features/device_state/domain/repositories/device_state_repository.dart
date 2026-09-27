import '../models/device_state_snapshot.dart';
import '../../../../core/domain/device_metric.dart';

/// Local state repository. Partner state has a separate type and read path
/// (`PartnerDeviceStateRepository` with [PartnerDeviceState]), so a remote
/// snapshot can never be handed out as this device's own state.
abstract interface class DeviceStateRepository {
  Future<DeviceStateSnapshot> getCurrentLocalState();
  Stream<DeviceStateSnapshot> watchLocalState();
  Future<DeviceStateSnapshot> refresh();
  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus;
}
