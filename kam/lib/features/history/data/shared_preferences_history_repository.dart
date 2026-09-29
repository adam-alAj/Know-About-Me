import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/sensitive_local_data.dart';
import '../domain/models/device_event.dart';
import '../domain/repositories/history_repository.dart';

/// Offline history cache. It retains at most 500 events and 180 days.
///
/// The cache is **not** namespaced by user, so reads must always be scoped by
/// `ownerUserId`. The provider layer does that, and the cache is additionally
/// removed when a session ends (`LocalStorageKeys.clearedOnSignOut`).
class SharedPreferencesHistoryRepository implements HistoryRepository {
  static const _key = LocalStorageKeys.history;
  static const maxEvents = 500;
  static const maxAge = Duration(days: 180);
  final DateTime Function() now;
  Future<void> _pendingWrites = Future<void>.value();

  SharedPreferencesHistoryRepository({DateTime Function()? now}) : now = now ?? DateTime.now;

  @override
  Future<void> add(DeviceEvent event) {
    final write = _pendingWrites.then((_) => _add(event));
    _pendingWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> _add(DeviceEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await _read(prefs);
    if (events.any((item) => item.id == event.id)) return;
    final cutoff = now().toUtc().subtract(maxAge);
    events.add(event);
    events.removeWhere((item) => item.occurredAt.isBefore(cutoff));
    events.sort(_compare);
    final bounded = events.length > maxEvents ? events.sublist(events.length - maxEvents) : events;
    await prefs.setString(_key, jsonEncode(bounded.map((item) => item.toJson()).toList()));
  }

  @override
  Future<List<DeviceEvent>> page({
    EventCategory? category,
    String? ownerUserId,
    int limit = 50,
    DateTime? before,
  }) async {
    await _pendingWrites;
    final prefs = await SharedPreferences.getInstance();
    final items = await _read(prefs);
    final selected = items.where((item) => (category == null || item.category == category) &&
        (ownerUserId == null || item.ownerUserId == ownerUserId) &&
        (before == null || item.occurredAt.isBefore(before))).toList()
      ..sort(_compare);
    return selected.take(limit.clamp(1, maxEvents).toInt()).toList();
  }

  @override
  Future<void> clearLocal() async {
    await _pendingWrites;
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  Future<List<DeviceEvent>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return <DeviceEvent>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final events = <DeviceEvent>[];
      for (final item in decoded) {
        try {
          final event = DeviceEvent.fromJson(Map<String, Object?>.from(item as Map));
          if (event.occurredAt.isAfter(now().toUtc().subtract(maxAge))) events.add(event);
        } on Object {
          // One malformed cached record must not hide valid history.
        }
      }
      events.sort(_compare);
      final bounded = events.length > maxEvents ? events.sublist(events.length - maxEvents) : events;
      if (bounded.length != decoded.length) {
        await prefs.setString(_key, jsonEncode(bounded.map((item) => item.toJson()).toList()));
      }
      return bounded;
    } on Object {
      await prefs.remove(_key);
      return <DeviceEvent>[];
    }
  }

  static int _compare(DeviceEvent a, DeviceEvent b) {
    final byTime = (b.recordedAt ?? b.occurredAt).compareTo(a.recordedAt ?? a.occurredAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}
