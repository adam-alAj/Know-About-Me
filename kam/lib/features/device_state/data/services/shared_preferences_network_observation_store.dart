import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/sensitive_local_data.dart';
import '../../domain/services/network_observation_store.dart';

class SharedPreferencesNetworkObservationStore
    implements NetworkObservationStore {
  static const _lastOnlineKey = LocalStorageKeys.lastOnlineAt;

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<DateTime?> readLastOnlineAt() async {
    final value = (await _preferences).getString(_lastOnlineKey);
    if (value == null) return null;
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      await (await _preferences).remove(_lastOnlineKey);
      return null;
    }
  }

  @override
  Future<void> writeLastOnlineAt(DateTime value) async {
    await (await _preferences).setString(
      _lastOnlineKey,
      value.toUtc().toIso8601String(),
    );
  }
}
