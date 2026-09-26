import 'app_environment.dart';

/// Compile-time application configuration.
///
/// Values are supplied with `--dart-define` (or `--dart-define-from-file`) and
/// are baked into the build. See `docs/architecture/FIREBASE_ARCHITECTURE.md` and
/// `ADR-004-configuration-strategy.md`, `ADR-007-firebase-integration.md`.
///
/// SECURITY (SRS NFR-029, constraint 5): this class must only ever hold values
/// that are safe to ship inside a mobile client. The Firebase values below are
/// **client configuration identifiers**, not secrets: they are present in every
/// FlutterFire app that ships with a `google-services.json`. Server-side
/// secrets — Firebase Admin service-account keys, private API keys, Cloud
/// Functions secrets — must never be referenced here and never be committed.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.enableVerboseLogging,
    this.firebaseProjectId,
    this.firebaseApiKey,
    this.firebaseAppId,
    this.firebaseMessagingSenderId,
    this.firebaseAuthDomain,
    this.firebaseStorageBucket,
    this.useFirebaseEmulators = false,
    this.firebaseEmulatorHost = 'localhost',
  });

  /// Reads configuration from the compiler environment.
  ///
  /// Sane development defaults are used so a developer can run the app with no
  /// extra flags. Firebase stays disabled until its client identifiers are
  /// provided, which is the honest default (no Firebase project is assumed).
  factory AppConfig.fromEnvironment() {
    const rawEnv = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const verbose = bool.fromEnvironment('ENABLE_VERBOSE_LOGGING');

    final environment = AppEnvironment.parse(rawEnv);

    return AppConfig(
      environment: environment,
      enableVerboseLogging: verbose || environment.allowsVerboseLogging,
      firebaseProjectId: _optional('FIREBASE_PROJECT_ID'),
      firebaseApiKey: _optional('FIREBASE_API_KEY'),
      firebaseAppId: _optional('FIREBASE_APP_ID'),
      firebaseMessagingSenderId: _optional('FIREBASE_MESSAGING_SENDER_ID'),
      firebaseAuthDomain: _optional('FIREBASE_AUTH_DOMAIN'),
      firebaseStorageBucket: _optional('FIREBASE_STORAGE_BUCKET'),
      useFirebaseEmulators: const bool.fromEnvironment(
        'FIREBASE_USE_EMULATORS',
      ),
      firebaseEmulatorHost: const String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: 'localhost',
      ),
    );
  }

  static String? _optional(String key) {
    final value = String.fromEnvironment(key);
    return value.isEmpty ? null : value;
  }

  /// The active deployment environment.
  final AppEnvironment environment;

  /// Whether verbose diagnostics are allowed.
  final bool enableVerboseLogging;

  // --- Firebase client configuration (client-safe) -------------------------

  /// Firebase project id, for example `know-about-me-dev`.
  final String? firebaseProjectId;

  /// Firebase Web/Android/iOS API key. A client identifier, not a secret.
  final String? firebaseApiKey;

  /// Firebase application id, for example `1:123:android:abc`.
  final String? firebaseAppId;

  /// Cloud Messaging sender id.
  final String? firebaseMessagingSenderId;

  /// Auth domain (used by the Web SDK).
  final String? firebaseAuthDomain;

  /// Cloud Storage bucket.
  final String? firebaseStorageBucket;

  /// Whether to point the SDKs at the local Firebase Emulator Suite.
  ///
  /// Must be false for any build that talks to real Firebase.
  final bool useFirebaseEmulators;

  /// Hostname of the Firebase Emulator Suite when [useFirebaseEmulators] is true.
  final String firebaseEmulatorHost;

  /// Whether the client has enough information to initialize Firebase.
  ///
  /// All four identifiers are required; a partial configuration is treated as
  /// "not configured" so the app fails closed instead of half-initializing.
  bool get hasFirebaseConfiguration =>
      firebaseProjectId != null &&
      firebaseApiKey != null &&
      firebaseAppId != null &&
      firebaseMessagingSenderId != null;

  /// Whether some, but not all, Firebase identifiers were supplied.
  ///
  /// Used to warn loudly about a misconfigured build rather than silently
  /// running without Firebase.
  bool get hasPartialFirebaseConfiguration =>
      !hasFirebaseConfiguration &&
      (firebaseProjectId != null ||
          firebaseApiKey != null ||
          firebaseAppId != null ||
          firebaseMessagingSenderId != null);

  /// Whether emulators were requested but Firebase itself is not configured.
  bool get hasMisconfiguredEmulatorRequest =>
      useFirebaseEmulators && !hasFirebaseConfiguration;

  @override
  String toString() =>
      'AppConfig(environment: ${environment.name}, '
      'verboseLogging: $enableVerboseLogging, '
      // Only the project id is echoed, and it is client-safe.
      'firebaseProjectId: $firebaseProjectId, '
      'emulators: $useFirebaseEmulators)';
}
