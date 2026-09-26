import '../config/app_config.dart';

/// Boundary between the application and Firebase.
///
/// ## Why this is a no-op in Phase 1
///
/// Phase 1 intentionally ships **without** the Firebase packages or
/// credentials (see `docs/decisions/ADR-002-firebase-boundaries.md`). Adding
/// Firebase before a project and its platform configuration files
/// (`google-services.json`, `GoogleService-Info.plist`) exist would either fail
/// the build or create an integration that appears to work but cannot run.
///
/// Phase 2 replaces the body of [FirebaseBootstrap.initialize] with a call to
/// `Firebase.initializeApp` and adds the FlutterFire dependencies. Until then
/// the application runs fully offline with placeholder data.
abstract final class FirebaseBootstrap {
  /// Whether Firebase was successfully initialized.
  ///
  /// Always false in Phase 1.
  static bool _initialized = false;

  /// Whether [initialize] has completed successfully.
  static bool get isInitialized => _initialized;

  /// Prepares Firebase. Safe to call unconditionally during startup.
  ///
  /// Returns `false` when Firebase is not configured for this build, which is
  /// the expected Phase 1 result.
  static Future<bool> initialize(AppConfig config) async {
    // Phase 2: when `config.hasFirebaseConfiguration` is true, await
    // Firebase.initializeApp(...) here and set `_initialized = true`.
    _initialized = false;
    return _initialized;
  }
}
