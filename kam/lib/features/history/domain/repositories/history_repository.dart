import '../models/device_event.dart';

abstract interface class HistoryRepository {
  Future<void> add(DeviceEvent event);

  /// Locally cached events, newest first.
  ///
  /// [ownerUserId] restricts the result to events recorded for that user, so a
  /// cached timeline can never be shown to a different account that signs in
  /// on the same device (SRS NFR-004). Passing `null` means "no owner filter"
  /// and is only appropriate for a store that is already user-scoped.
  Future<List<DeviceEvent>> page({
    EventCategory? category,
    String? ownerUserId,
    int limit = 50,
    DateTime? before,
  });

  Future<void> clearLocal();
}
