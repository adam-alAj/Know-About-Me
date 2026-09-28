import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/firebase/firebase_bootstrap.dart';
import '../core/logging/app_logger.dart';
import '../core/notifications/local_notification_service.dart';
import '../core/platform/platform_info.dart';
import '../core/time/clock.dart';

/// The resolved application configuration.
///
/// Overridden in `AppBootstrap.run()` and in tests, so widgets and features never
/// read the compiler environment directly.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError(
    'appConfigProvider must be overridden in ProviderScope (see AppBootstrap)',
  ),
);

/// The application clock.
///
/// Overriding this with a `FixedClock` makes freshness-dependent UI and rule
/// evaluation deterministic in tests (SRS NFR-018, NFR-033).
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Whether the Firebase boundary has been initialized.
///
/// Always false in Phase 2; Phase 3 wires the real initialization.
final firebaseReadyProvider = Provider<bool>(
  (ref) => FirebaseBootstrap.isInitialized,
);

/// Reports the current platform behind an interface, so no feature reads
/// Flutter's `defaultTargetPlatform` directly (SRS constraint 3).
final platformInfoProvider = Provider<PlatformInfo>(
  (ref) => const FlutterPlatformInfo(),
);

/// The device-local notification service.
///
/// Defaults to the honest no-op implementation that reports itself
/// unsupported. A real platform binding is a notification-phase task; until
/// then the app must never claim it delivered an alert it did not
/// (see `docs/architecture/SPARK_ONLY_ARCHITECTURE.md` §4).
final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => const MethodChannelLocalNotificationService(),
);

/// The application logger.
///
/// Level is derived from configuration, so production builds do not emit debug
/// noise without any call-site changes (SRS NFR-045).
final loggerProvider = Provider<AppLogger>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.enableVerboseLogging
      ? const DeveloperAppLogger()
      : const DeveloperAppLogger(minimumLevel: LogLevel.info);
});
