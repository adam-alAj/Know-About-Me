import 'app_environment.dart';

/// Compile-time application configuration.
///
/// Values are supplied with `--dart-define` (or `--dart-define-from-file`) and
/// are baked into the build. See `docs/architecture/ARCHITECTURE.md` and
/// ADR-004 for the configuration strategy.
///
/// SECURITY (SRS NFR-029, constraint 5): this class must only ever hold values
/// that are safe to ship inside a mobile client. Server-side secrets — Firebase
/// Admin service-account keys, private API keys, Cloud Functions secrets — must
/// never be referenced here and must never be committed to this repository.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.enableVerboseLogging,
    this.firebaseProjectId,
  });

  /// Reads configuration from the compiler environment.
  ///
  /// Sane development defaults are used so that a developer can run the app
  /// without any extra flags.
  factory AppConfig.fromEnvironment() {
    const rawEnv = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const verbose = bool.fromEnvironment('ENABLE_VERBOSE_LOGGING');
    const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

    final environment = AppEnvironment.parse(rawEnv);

    return AppConfig(
      environment: environment,
      enableVerboseLogging: verbose || environment.allowsVerboseLogging,
      firebaseProjectId: firebaseProjectId.isEmpty ? null : firebaseProjectId,
    );
  }

  /// The active deployment environment.
  final AppEnvironment environment;

  /// Whether verbose diagnostics are allowed.
  final bool enableVerboseLogging;

  /// Public Firebase project id.
  ///
  /// A Firebase project id is not a secret: it is present in every client app.
  /// It is listed here only so that Phase 2 can select the right backend.
  final String? firebaseProjectId;

  /// Whether the client has enough information to initialize Firebase.
  ///
  /// Phase 1 deliberately ships without Firebase credentials, so this is
  /// normally false (see ADR-002).
  bool get hasFirebaseConfiguration => firebaseProjectId != null;

  @override
  String toString() =>
      'AppConfig(environment: ${environment.name}, '
      'verboseLogging: $enableVerboseLogging, '
      'firebaseProjectId: $firebaseProjectId)';
}
