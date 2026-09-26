/// Central route table: names and paths used by navigation.
///
/// Keeping these in one place means a future authentication or pairing guard can
/// redirect to a known name without string literals scattered through the UI.
abstract final class AppRoutes {
  // Top-level destinations of the main shell.
  static const String dashboard = 'dashboard';
  static const String rules = 'rules';
  static const String history = 'history';
  static const String privacy = 'privacy';

  // Pages pushed above the shell.
  static const String profile = 'profile';

  // Reserved for later phases; declared now so guards can reference them.
  static const String signIn = 'sign-in';
  static const String pairing = 'pairing';

  static const String dashboardPath = '/';
  static const String rulesPath = '/rules';
  static const String historyPath = '/history';
  static const String privacyPath = '/privacy';
  static const String profilePath = '/profile';
  static const String signInPath = '/sign-in';
  static const String pairingPath = '/pairing';
}
