import '../../domain/models/device_state_snapshot.dart';
import '../../../../core/domain/device_metric.dart';
import '../../domain/repositories/device_state_repository.dart';
import '../../domain/sources/device_state_provider.dart';

/// In-memory local snapshot cache. It never accepts partner state.
class LocalDeviceStateRepository implements DeviceStateRepository {
  LocalDeviceStateRepository(this._provider);
  final DeviceStateProvider _provider;
  DeviceStateSnapshot? _cached;

  @override
  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus =>
      _provider.getCapabilityStatus();

  @override
  Future<DeviceStateSnapshot> getCurrentLocalState() async =>
      _cached ??= await _provider.getCurrentState();

  @override
  Stream<DeviceStateSnapshot> watchLocalState() => _provider.watchState().map((snapshot) {
    _cached = snapshot;
    return snapshot;
  });

  @override
  Future<DeviceStateSnapshot> refresh() async =>
      _cached = await _provider.getCurrentState();
}
