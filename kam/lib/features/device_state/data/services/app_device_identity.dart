import 'dart:math';

import '../../domain/services/device_identity_store.dart';

/// Generates a random 128-bit identifier and persists it through the injected
/// store. It is an application record key, never an authorization credential.
class AppDeviceIdentity {
  AppDeviceIdentity(this._store, {Random? random}) : _random = random ?? Random.secure();

  final DeviceIdentityStore _store;
  final Random _random;

  Future<String> getOrCreate() async {
    final stored = await _store.read();
    if (_isValid(stored)) return stored!;
    final id = List<int>.generate(16, (_) => _random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _store.write(id);
    return id;
  }

  static bool _isValid(String? value) => value != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(value);
}
