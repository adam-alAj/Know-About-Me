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
    bool useGeneratedFirebaseOptions = false,
    AppLogger? logger,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();

    final config = AppConfig.fromEnvironment();
    final activeLogger = logger ?? _loggerFor(config);
    activeLogger.info(
      'Application starting',
      context: {'environment': config.environment.name},
    );

    // Firebase is initialized here and only here (never from a widget).
    final firebaseReady = await FirebaseBootstrap.initialize(
      config,
      useGeneratedOptions: useGeneratedFirebaseOptions,
      logger: activeLogger,
    );
    if (!firebaseReady) {
      final failure = FirebaseBootstrap.lastFailure;
      if (failure != null) {
        // Initialization was attempted and failed: report it, but keep going so
        // the app degrades instead of refusing to start (NFR-014, NFR-015).
        activeLogger.warning('Continuing without Firebase: ${failure.message}');
      } else {
        activeLogger.info(
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
    WidgetsFlutterBinding.ensureInitialized();
    final config = AppConfig.fromEnvironment();
    final logger = _loggerFor(config);
    if (!kIsWeb) AppErrorBoundary.install(logger: logger);

    try {
      await initialize(
        useGeneratedFirebaseOptions: true,
        logger: logger,
      );
      runApp(
        ProviderScope(
          overrides: [appConfigProvider.overrideWithValue(config)],
          child: KamApp(config: config),
        ),
      );
    } catch (error, stackTrace) {
      logger.error(
        'Application startup failed',
        error: error,
        stackTrace: stackTrace,
        context: {'errorType': error.runtimeType.toString()},
      );
      runApp(const _StartupFailureApp());
    }
  }

  static AppLogger _loggerFor(AppConfig config) => config.enableVerboseLogging
      ? const DeveloperAppLogger()
      : const DeveloperAppLogger(
          minimumLevel: LogLevel.warning,
          includeErrorDetails: false,
        );
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The app could not finish starting. Your account data has not been changed. Try again, or close and reopen the app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: AppBootstrap.run,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
