import '../models/device_event.dart';

abstract interface class HistoryRepository {
  Future<void> add(DeviceEvent event);
  Future<List<DeviceEvent>> page({EventCategory? category, int limit = 50, DateTime? before});
  Future<void> clearLocal();
}
