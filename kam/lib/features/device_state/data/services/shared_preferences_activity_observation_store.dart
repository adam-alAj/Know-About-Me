import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/activity_observation_store.dart';

class SharedPreferencesActivityObservationStore
    implements ActivityObservationStore {
  static const _lastObservedKey = 'device_state.last_observed_activity_at';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<DateTime?> readLastObservedActivityAt() async {
    final value = (await _preferences).getString(_lastObservedKey);
    if (value == null) return null;
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      await (await _preferences).remove(_lastObservedKey);
      return null;
    }
  }

  @override
  Future<void> writeLastObservedActivityAt(DateTime value) async {
    await (await _preferences).setString(
      _lastObservedKey,
      value.toUtc().toIso8601String(),
    );
  }
}
