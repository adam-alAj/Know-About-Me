import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../error/app_failure.dart';
import '../logging/app_logger.dart';
import 'firebase_config.dart';
import 'firebase_emulators.dart';
import 'firebase_error_mapper.dart';

/// Boundary between the application and Firebase.
///
/// ## Behaviour
///
/// - Firebase is initialized **only** when [AppConfig.hasFirebaseConfiguration]
///   is true. Otherwise initialization is skipped and the application continues
///   offline with explicit non-available states (SRS constraint 10: no
///   fabricated Firebase resources).
/// - Initialization happens exactly once, from `AppBootstrap`, never from a
///   widget or feature.
/// - A failure is classified into an [AppFailure], retained in [lastFailure] for
///   reporting, logged without secrets, and **never thrown** to the caller, so a
///   backend problem cannot prevent the app from starting (NFR-014, NFR-015).
/// - Device-state and location features do not depend on this class; they depend
///   on their own repositories/sources, so Firebase stays replaceable.
///
/// Phase 3 initializes the SDK and connects emulators only. Authentication flows,
/// Firestore repositories and messaging handlers arrive in later phases.
abstract final class FirebaseBootstrap {
  static bool _initialized = false;
  static AppFailure? _lastFailure;

  /// Whether Firebase was successfully initialized for this process.
  static bool get isInitialized => _initialized;

  /// The classified failure from the last attempt, if it failed.
  ///
  /// `null` means either "not configured" (an expected state) or "succeeded".
  static AppFailure? get lastFailure => _lastFailure;

  /// Prepares Firebase. Safe to call unconditionally during startup.
  ///
  /// Returns `true` only when the SDK actually initialized.
  static Future<bool> initialize(
    AppConfig config, {
    AppLogger logger = const DeveloperAppLogger(),
  }) async {
    _lastFailure = null;

    if (config.hasPartialFirebaseConfiguration) {
      // Loud, but non-fatal: a half-configured build is a configuration bug.
      logger.warning(
        'Firebase configuration is incomplete; continuing without Firebase.',
        context: {'environment': config.environment.name},
      );
      _initialized = false;
      return false;
    }

    if (!FirebaseConfig.isConfigured(config)) {
      logger.info(
        'Firebase is not configured for this build; continuing offline.',
      );
      _initialized = false;
      return false;
    }

    try {
      await Firebase.initializeApp(options: FirebaseConfig.optionsFor(config));

      // Local development points at the Emulator Suite so it can never write to
      // production data. Emulator connection failures are non-fatal.
      FirebaseEmulators.connect(config, logger: logger);

      _initialized = true;
      logger.info(
        'Firebase initialized',
        context: {
          'environment': config.environment.name,
          'emulators': config.useFirebaseEmulators,
        },
      );
      return true;
    } catch (error, stackTrace) {
      final failure = FirebaseErrorMapper.toFailure(error, stackTrace);
      _lastFailure = failure;
      _initialized = false;
      logger.error(
        'Firebase initialization failed; continuing without Firebase.',
        error: error,
        stackTrace: stackTrace,
        context: {'failureType': failure.type.name},
      );
      return false;
    }
  }

  /// Releases the Firebase app. Test-only helper.
  @visibleForTesting
  static Future<void> reset() async {
    if (_initialized) {
      try {
        await Firebase.app().delete();
      } catch (_) {
        // Best effort: only the test harness calls this.
      }
    }
    _initialized = false;
    _lastFailure = null;
  }
}
