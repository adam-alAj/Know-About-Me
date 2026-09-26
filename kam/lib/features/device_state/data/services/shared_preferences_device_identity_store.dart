import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/device_identity_store.dart';

/// Persists the non-secret opaque ID in app-private preferences.
class SharedPreferencesDeviceIdentityStore implements DeviceIdentityStore {
  static const _key = 'device_state.opaque_device_id';
  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<String?> read() async => (await _preferences).getString(_key);

  @override
  Future<void> write(String value) async {
    await (await _preferences).setString(_key, value);
  }

  @override
  Future<void> remove() async {
    await (await _preferences).remove(_key);
  }
}
