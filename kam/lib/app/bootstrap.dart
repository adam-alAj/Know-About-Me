import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/firebase/firebase_bootstrap.dart';
import '../core/logging/app_logger.dart';
import 'app.dart';
import 'error_boundary.dart';
import 'providers.dart';

/// Application startup sequence.
///
/// ```
/// main()
///   → AppBootstrap.initialize()   configure, log, prepare services
///   → ProviderScope               install dependency overrides
///   → KamApp                      root widget
///   → router                      initial screen
/// ```
///
/// Startup logic lives here rather than in a widget so it can be tested and so
/// future work (Firebase, auth state, local persistence, notification services)
/// has one obvious place to be added without touching UI (SRS Task 3).
abstract final class AppBootstrap {
  /// Configures and prepares the application. Safe to call from tests.
  ///
  /// Does **not** start any widget tree.
  static Future<AppConfig> initialize({
    AppLogger logger = const DeveloperAppLogger(),
  }) async {
    WidgetsFlutterBinding.ensureInitialized();

    final config = AppConfig.fromEnvironment();
    logger.info(
      'Application starting',
      context: {'environment': config.environment.name},
    );

    // Firebase is initialized here and only here (never from a widget).
    final firebaseReady = await FirebaseBootstrap.initialize(
      config,
      logger: logger,
    );
    if (!firebaseReady) {
      final failure = FirebaseBootstrap.lastFailure;
      if (failure != null) {
        // Initialization was attempted and failed: report it, but keep going so
        // the app degrades instead of refusing to start (NFR-014, NFR-015).
        logger.warning('Continuing without Firebase: ${failure.message}');
      } else {
        logger.info(
          'Firebase is not configured for this build; continuing offline.',
        );
      }
    }

    // Future services slot in here: auth state, local persistence,
    // notification handling, background monitoring registration.

    return config;
  }

  /// Initializes the application and runs the root widget.
  static Future<void> run() async {
    final config = await initialize();

    // Compose-time guard: show a calm fallback if a widget fails to build.
    if (!kIsWeb) AppErrorBoundary.install();

    runApp(
      ProviderScope(
        overrides: [appConfigProvider.overrideWithValue(config)],
        child: KamApp(config: config),
      ),
    );
  }
}
