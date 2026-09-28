/// Central route table: names and paths used by navigation.
///
/// Keeping these in one place means the authentication guard (and any later
/// pairing guard) can redirect to a known name without string literals scattered
/// through the UI.
abstract final class AppRoutes {
  // Startup and authentication.
  static const String splash = 'splash';
  static const String signIn = 'sign-in';
  static const String createAccount = 'create-account';

  // Top-level destinations of the main shell.
  static const String dashboard = 'dashboard';
  static const String rules = 'rules';
  static const String history = 'history';
  static const String privacy = 'privacy';

  // Pages pushed above the shell.
  static const String profile = 'profile';

  // Rule builder, nested under the rules destination.
  static const String ruleCreate = 'rule-create';
  static const String ruleEdit = 'rule-edit';

  // Reserved for the pairing phase; declared now so guards can reference it.
  static const String pairing = 'pairing';

  static const String splashPath = '/splash';
  static const String signInPath = '/sign-in';
  static const String createAccountPath = '/create-account';
  static const String dashboardPath = '/';
  static const String rulesPath = '/rules';
  static const String historyPath = '/history';
  static const String privacyPath = '/privacy';
  static const String profilePath = '/profile';
  static const String pairingPath = '/pairing';
  static const String ruleCreatePath = '/rules/new';

  /// The builder location for an existing rule.
  static String ruleEditPath(String ruleId) => '/rules/$ruleId/edit';
}
