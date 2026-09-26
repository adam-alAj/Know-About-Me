import 'package:firebase_core/firebase_core.dart';

import '../config/app_config.dart';

/// Builds [FirebaseOptions] from [AppConfig].
///
/// FlutterFire's `flutterfire configure` normally generates a
/// `firebase_options.dart` file from a real project. That command needs a
/// Firebase project and credentials, which are not available in this
/// environment, and fabricating one would be dishonest (see
/// `docs/PHASE_03_COMPLETION_REPORT.md`, constraint 10).
///
/// Instead, options are assembled from client-safe compile-time values, which is
/// the FlutterFire-supported alternative to bundling `google-services.json`.
/// This also means the build does not require the `com.google.gms.google-services`
/// Gradle plugin, and the same binary can target a different environment by
/// changing `--dart-define` values.
abstract final class FirebaseConfig {
  /// Whether the configuration is complete enough to initialize Firebase.
  static bool isConfigured(AppConfig config) => config.hasFirebaseConfiguration;

  /// Assembles [FirebaseOptions] for [config].
  ///
  /// Throws [StateError] when the configuration is incomplete; callers must
  /// check [isConfigured] first. This keeps a half-configured build from
  /// silently initializing against the wrong (or no) project.
  static FirebaseOptions optionsFor(AppConfig config) {
    if (!config.hasFirebaseConfiguration) {
      throw StateError(
        'Firebase is not configured. Provide FIREBASE_PROJECT_ID, '
        'FIREBASE_API_KEY, FIREBASE_APP_ID and FIREBASE_MESSAGING_SENDER_ID '
        'via --dart-define. See docs/architecture/FIREBASE_ARCHITECTURE.md.',
      );
    }

    return FirebaseOptions(
      apiKey: config.firebaseApiKey!,
      appId: config.firebaseAppId!,
      messagingSenderId: config.firebaseMessagingSenderId!,
      projectId: config.firebaseProjectId!,
      authDomain: config.firebaseAuthDomain,
      storageBucket: config.firebaseStorageBucket,
    );
  }
}
