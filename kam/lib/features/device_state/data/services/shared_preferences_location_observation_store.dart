import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/sensitive_local_data.dart';
import '../../domain/models/device_location_state.dart';
import '../../domain/services/location_observation_store.dart';

/// Persists exactly one location fix as JSON under a single key.
///
/// No history, no trail: the previous fix is overwritten by the next one. The
/// stored `observedAt` is the platform's own fix time and is never rewritten on
/// read, so a restored fix reports its true age.
class SharedPreferencesLocationObservationStore
    implements LocationObservationStore {
  static const _lastKnownKey = LocalStorageKeys.lastKnownLocation;

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<LocationFix?> readLastKnownFix() async {
    final raw = (await _preferences).getString(_lastKnownKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Not an object');
      return LocationFix.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      await (await _preferences).remove(_lastKnownKey);
      return null;
    }
  }

  @override
  Future<void> writeLastKnownFix(LocationFix fix) async {
    await (await _preferences).setString(
      _lastKnownKey,
      jsonEncode(fix.toJson()),
    );
  }
}
