import 'package:shared_preferences/shared_preferences.dart';

import '../error/app_failure.dart';
import '../logging/app_logger.dart';

/// The `shared_preferences` keys this application uses for **sensitive local
/// state**.
///
/// They live in one place so that the stores which write them and the sign-out
/// cleaner which removes them cannot drift apart: a new cached value that is not
/// listed here is a value that survives a sign-out, and that is exactly the
/// mistake the security model forbids (NFR-004, NFR-045).
///
/// Device-scoped bookkeeping ([deviceIdentity], [syncVersion]) is deliberately
/// **not** cleared on sign-out:
///
/// * [deviceIdentity] identifies the handset, not the account, and is a random
///   opaque value — never a hardware identifier and never an authorization
///   credential.
/// * [syncVersion] is a monotonic per-device counter the Security Rules use to
///   reject regressing state writes. Resetting it would make this device's next
///   legitimate write look older than the stored document and get rejected.
abstract final class LocalStorageKeys {
  /// Bounded offline history cache.
  static const String history = 'history_events_v1';

  /// The single most recent location fix (overwritten, never a trail).
  static const String lastKnownLocation = 'device_state.last_known_location';

  /// The last observed application-activity timestamp.
  static const String lastObservedActivityAt =
      'device_state.last_observed_activity_at';

  /// The last time this device observed itself online.
  static const String lastOnlineAt = 'device_state.last_online_at';

  /// Opaque, application-generated device id (device-scoped, not user-scoped).
  static const String deviceIdentity = 'device_state.opaque_device_id';

  /// Monotonic synchronization version counter (device-scoped).
  static const String syncVersion = 'device_state.sync_version';

  /// Everything that must be removed when the authenticated session ends.
  ///
  /// This is user-derived, privacy-sensitive cache: a location fix, activity and
  /// connectivity observations, and a history timeline. None of it may outlive
  /// the session, because another account can sign in on the same device.
  static const List<String> clearedOnSignOut = <String>[
    history,
    lastKnownLocation,
    lastObservedActivityAt,
    lastOnlineAt,
  ];
}

/// Removes protected local state when a session ends.
///
/// The interface exists so the authentication layer can depend on the *ability*
/// to clear local data without importing the feature stores that write it; the
/// key list stays in [LocalStorageKeys].
abstract interface class SensitiveLocalData {
  /// Removes every key in [LocalStorageKeys.clearedOnSignOut].
  ///
  /// Must be idempotent and must never throw: it runs on the sign-out path, and
  /// a storage failure there must not leave the user unable to sign out.
  Future<void> clear();
}

/// `shared_preferences`-backed implementation.
class SharedPreferencesSensitiveLocalData implements SensitiveLocalData {
  const SharedPreferencesSensitiveLocalData({
    this.logger = const NoopAppLogger(),
  });

  final AppLogger logger;

  @override
  Future<void> clear() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      for (final key in LocalStorageKeys.clearedOnSignOut) {
        await preferences.remove(key);
      }
    } catch (error, stackTrace) {
      // Best effort by contract: the session is ending either way, and the
      // production implementation only fails when platform storage is missing
      // (for example in a unit-test host).
      final failure = LocalStorageFailure(
        'Protected local data could not be fully cleared.',
        cause: error,
        stackTrace: stackTrace,
      );
      logger.warning(
        'Sensitive local session data could not be fully cleared',
        context: {'failureType': failure.type.name},
      );
    }
  }
}
