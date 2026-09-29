import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/sensitive_local_data.dart';
import '../../domain/sources/sync_version_store.dart';

/// Persists the monotonic synchronization version counter locally.
///
/// It is app-private bookkeeping, not a secret and not a credential: it only
/// lets this device recognise its own older writes.
class SharedPreferencesSyncVersionStore implements SyncVersionStore {
  static const _key = LocalStorageKeys.syncVersion;

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<int> read() async {
    final value = (await _preferences).getInt(_key);
    return value == null || value < 0 ? 0 : value;
  }

  @override
  Future<void> write(int version) async {
    await (await _preferences).setInt(_key, version);
  }
}
