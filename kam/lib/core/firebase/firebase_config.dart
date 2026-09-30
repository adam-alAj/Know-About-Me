import 'package:firebase_core/firebase_core.dart';

import '../config/app_config.dart';

/// Builds alternate [FirebaseOptions] from [AppConfig].
///
/// Normal app startup opts into generated FlutterFire options. Complete
/// client-safe compile-time identifiers override those generated defaults; they
/// are not privileged credentials. The Android build does not apply the Google
/// Services Gradle plugin because initialization uses Dart options.
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
