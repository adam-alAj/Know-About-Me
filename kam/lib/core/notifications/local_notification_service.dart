import '../error/app_failure.dart';
import '../result/result.dart';

/// A notification the **device itself** raises, without any server.
///
/// This is the Spark-compatible notification path: when the app is running and
/// observing authorized partner state, a matched rule produces an
/// interpretation, and the device raises its own local notification. No Cloud
/// Function, no Admin credential and no FCM server key is involved
/// (see `docs/architecture/SPARK_ONLY_ARCHITECTURE.md` §4).
class LocalNotificationRequest {
  const LocalNotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  /// Stable id used to replace rather than duplicate a visible notification.
  final String id;

  /// Short title. Must not expose more private information than the user would
  /// see in the app itself (FR-043).
  final String title;

  /// Message body, for example
  /// "There is a 70% possibility that Afraa is sleeping now."
  final String body;

  /// Optional opaque payload for deep-linking when the notification is tapped.
  final String? payload;

  @override
  String toString() => 'LocalNotificationRequest($id, "$title")';
}

/// Abstraction over the platform's local-notification mechanism.
///
/// Deliberately narrow: it can raise and clear notifications on this device and
/// nothing else. There is no `send(toDevice)` method, because a client must
/// never be able to push to another device — that would require a server
/// credential the app is not allowed to hold (constraint: no privileged
/// credentials in Flutter).
abstract interface class LocalNotificationService {
  /// Whether this platform/host can actually raise local notifications.
  ///
  /// Callers must check this before promising the user a notification, so the
  /// app can honestly say "notifications are unavailable here" instead of
  /// silently doing nothing.
  bool get isSupported;

  /// Raises (or replaces) a notification on this device.
  ///
  /// Returns a [Failure] rather than throwing when the capability is absent, so
  /// a notification problem can never crash the rule pipeline.
  Future<Result<void>> show(LocalNotificationRequest request);

  /// Removes all notifications raised by the application.
  Future<Result<void>> cancelAll();
}

/// The honest default while no platform binding exists.
///
/// It reports `isSupported == false` and returns a classified
/// [UnsupportedCapabilityFailure] instead of pretending the notification was
/// delivered. The underlying interpretation is still persisted and shown in the
/// app, so no information is lost (FR-044: a missed delivery never removes the
/// event from history).
///
/// Binding a real implementation (for example `flutter_local_notifications`) is
/// a notification-phase task; see `PHASE_10` in the requirement mapping.
class UnavailableLocalNotificationService implements LocalNotificationService {
  const UnavailableLocalNotificationService();

  @override
  bool get isSupported => false;

  @override
  Future<Result<void>> show(LocalNotificationRequest request) async {
    return const Failure<void>(
      UnsupportedCapabilityFailure(
        'This device cannot show local notifications yet. '
        'The alert is still recorded in your notification history.',
      ),
    );
  }

  @override
  Future<Result<void>> cancelAll() async => const Success<void>(null);
}
