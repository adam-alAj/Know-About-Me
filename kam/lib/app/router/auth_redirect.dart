import '../../features/auth/domain/models/auth_state.dart';
import 'app_routes.dart';

/// Decides where each location should actually go, given the authentication
/// state (SRS Task 9, Task 10).
///
/// A pure function on purpose: every routing case — including the ones that are
/// awkward to trigger in a widget test, such as an authentication outage or a
/// session revoked mid-use — is a plain unit test. The router merely calls it.
///
/// Deny-by-default is the core rule: only a small set of locations is reachable
/// while unauthenticated, so a protected screen cannot be opened by typing its
/// path, and hiding navigation controls is not what protects it (Phase 4 Task 9).
abstract final class AuthRedirect {
  /// Locations reachable **only** while signed out.
  static const Set<String> _authRoutes = <String>{
    AppRoutes.signInPath,
    AppRoutes.createAccountPath,
  };

  /// Locations that show application data and therefore require an established
  /// identity.
  static const Set<String> _protectedRoutes = <String>{
    AppRoutes.dashboardPath,
    AppRoutes.rulesPath,
    AppRoutes.historyPath,
    AppRoutes.privacyPath,
    AppRoutes.profilePath,
  };

  /// Returns the location to redirect to, or `null` to allow [location].
  ///
  /// | Authentication state | Unauthenticated-only route | Protected route |
  /// | --- | --- | --- |
  /// | initializing / error | splash | splash |
  /// | unauthenticated | allow | sign-in |
  /// | authenticating (was signed out) | allow | sign-in |
  /// | authenticating (was signed in) | dashboard | allow |
  /// | authenticated / signing out | dashboard | allow |
  static String? resolve({
    required AuthState authState,
    required String location,
  }) {
    final onSplash = location == AppRoutes.splashPath;
    final isAuthRoute = _authRoutes.contains(location);

    switch (authState) {
      // Never show an application screen before authorization is known, and
      // never fail into a blank authenticated shell. Routes that hold no
      // application data (the sign-in screens, and the not-found screen for an
      // unrecognised path) are allowed through, so a deep link is not silently
      // rewritten and the not-found screen still works on a cold start.
      case AuthInitializing():
        if (onSplash || !_protectedRoutes.contains(location)) return null;
        return AppRoutes.splashPath;

      // An undeterminable session goes to the splash screen from anywhere, so
      // the app states the problem and offers a retry instead of presenting a
      // sign-in form that cannot currently work.
      case AuthError():
        return onSplash ? null : AppRoutes.splashPath;

      // Signed out: the authentication flow, and nothing else.
      case AuthUnauthenticated():
        return isAuthRoute ? null : AppRoutes.signInPath;

      case AuthAuthenticating(:final previous):
        if (previous == null) {
          // Still effectively signed out, so stay in the authentication flow.
          return isAuthRoute ? null : AppRoutes.signInPath;
        }
        // A re-authentication: keep the signed-in user where they are instead of
        // bouncing them through the sign-in screen again.
        return _leaveAuthArea(location);

      // Signed in (including mid-sign-out, which deliberately does not redirect:
      // a bounce here would be visible as flicker, SRS Task 10).
      case AuthAuthenticated():
      case AuthSigningOut():
        return _leaveAuthArea(location);
    }
  }

  /// Sends a signed-in user out of the authentication area (and off the splash).
  static String? _leaveAuthArea(String location) {
    if (_authRoutes.contains(location) || location == AppRoutes.splashPath) {
      return AppRoutes.dashboardPath;
    }
    return null;
  }
}
