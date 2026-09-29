import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kam/core/storage/sensitive_local_data.dart';

/// Phase 19: local data lifecycle.
///
/// The app caches a location fix, activity/connectivity observations and a
/// history timeline in app-private preferences. None of it may outlive the
/// session, because another account can sign in on the same device
/// (SRS NFR-004).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clears protected local state and keeps device bookkeeping', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LocalStorageKeys.history: '[]',
      LocalStorageKeys.lastKnownLocation: '{"latitude":52.5,"longitude":13.4}',
      LocalStorageKeys.lastObservedActivityAt: '2026-01-01T00:00:00.000Z',
      LocalStorageKeys.lastOnlineAt: '2026-01-01T00:00:00.000Z',
      // Device-scoped: identifies the handset, not the account.
      LocalStorageKeys.deviceIdentity: '0f8fad5bdb1e3e4f',
      LocalStorageKeys.syncVersion: 7,
    });

    await const SharedPreferencesSensitiveLocalData().clear();

    final preferences = await SharedPreferences.getInstance();
    for (final key in LocalStorageKeys.clearedOnSignOut) {
      expect(
        preferences.containsKey(key),
        isFalse,
        reason: '$key must not survive a sign-out',
      );
    }

    // The opaque device id is not user data, and the monotonic sync version must
    // survive: resetting it would make this device's next legitimate state write
    // look older than the stored document and be rejected by the rules.
    expect(preferences.getString(LocalStorageKeys.deviceIdentity), isNotNull);
    expect(preferences.getInt(LocalStorageKeys.syncVersion), 7);
  });

  test('clearing is idempotent and never throws', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await const SharedPreferencesSensitiveLocalData().clear();
    await const SharedPreferencesSensitiveLocalData().clear();
  });

  test('every cleared key is declared in the shared key list', () {
    // Guards against a new sensitive store being added without a lifecycle.
    expect(
      LocalStorageKeys.clearedOnSignOut,
      containsAll(<String>[
        LocalStorageKeys.history,
        LocalStorageKeys.lastKnownLocation,
        LocalStorageKeys.lastObservedActivityAt,
        LocalStorageKeys.lastOnlineAt,
      ]),
    );
  });
}
