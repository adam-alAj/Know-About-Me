/// Deployment environments the application can run against.
///
/// The active environment is selected at build time via `--dart-define=APP_ENV=...`
/// and defaults to [AppEnvironment.development] (SRS NFR-029, Task 8).
enum AppEnvironment {
  development,
  staging,
  production;

  /// Parses a raw `APP_ENV` value, falling back to development.
  static AppEnvironment parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.development;
    }
  }

  /// Whether extra diagnostics may be emitted for this environment.
  bool get allowsVerboseLogging => this != AppEnvironment.production;
}
