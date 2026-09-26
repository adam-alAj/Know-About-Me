import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/router/app_routes.dart';
import 'package:kam/app/router/auth_redirect.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/domain/models/auth_state.dart';

void main() {
  const identity = AuthIdentity(uid: 'user-a', email: 'afraa@example.com');

  String? resolve(AuthState state, String location) =>
      AuthRedirect.resolve(authState: state, location: location);

  group('while the authentication state is unknown', () {
    test('routes that show application data go to the splash screen', () {
      for (final location in [
        AppRoutes.dashboardPath,
        AppRoutes.rulesPath,
        AppRoutes.historyPath,
        AppRoutes.privacyPath,
        AppRoutes.profilePath,
      ]) {
        // Protected content must not be visible before authorization is known.
        expect(
          resolve(const AuthInitializing(), location),
          AppRoutes.splashPath,
          reason: '$location must not render while initializing',
        );
      }
    });

    test('routes that hold no application data are left alone', () {
      // Nothing sensitive is exposed, and rewriting an unrecognised path would
      // break the not-found screen on a cold start.
      expect(resolve(const AuthInitializing(), AppRoutes.signInPath), isNull);
      expect(
        resolve(const AuthInitializing(), AppRoutes.createAccountPath),
        isNull,
      );
      expect(resolve(const AuthInitializing(), '/does-not-exist'), isNull);
    });

    test('the splash screen itself is allowed', () {
      expect(resolve(const AuthInitializing(), AppRoutes.splashPath), isNull);
    });

    test(
      'an authentication outage goes to the splash screen from anywhere',
      () {
        const state = AuthError(
          RemoteServiceFailure('Account service is down'),
        );

        expect(resolve(state, AppRoutes.dashboardPath), AppRoutes.splashPath);
        expect(resolve(state, AppRoutes.signInPath), AppRoutes.splashPath);
        expect(
          resolve(state, AppRoutes.createAccountPath),
          AppRoutes.splashPath,
        );
        expect(resolve(state, '/does-not-exist'), AppRoutes.splashPath);
        // The splash screen itself is the destination, so there is no loop.
        expect(resolve(state, AppRoutes.splashPath), isNull);
      },
    );
  });

  group('while signed out', () {
    const state = AuthUnauthenticated();

    test('protected routes are denied by default', () {
      for (final location in [
        AppRoutes.dashboardPath,
        AppRoutes.rulesPath,
        AppRoutes.historyPath,
        AppRoutes.privacyPath,
        AppRoutes.profilePath,
      ]) {
        expect(
          resolve(state, location),
          AppRoutes.signInPath,
          reason: '$location must not be reachable while signed out',
        );
      }
    });

    test('the authentication flow is allowed', () {
      expect(resolve(state, AppRoutes.signInPath), isNull);
      expect(resolve(state, AppRoutes.createAccountPath), isNull);
    });

    test('the splash screen is left behind once the state is known', () {
      expect(resolve(state, AppRoutes.splashPath), AppRoutes.signInPath);
    });
  });

  group('while signing in', () {
    test('stays in the authentication flow when previously signed out', () {
      const state = AuthAuthenticating();

      expect(resolve(state, AppRoutes.signInPath), isNull);
      expect(resolve(state, AppRoutes.createAccountPath), isNull);
      expect(resolve(state, AppRoutes.dashboardPath), AppRoutes.signInPath);
    });

    test('keeps a re-authenticating user where they are', () {
      const state = AuthAuthenticating(previous: identity);

      // No bounce through the sign-in screen during a re-authentication.
      expect(resolve(state, AppRoutes.dashboardPath), isNull);
      expect(resolve(state, AppRoutes.profilePath), isNull);
      expect(resolve(state, AppRoutes.signInPath), AppRoutes.dashboardPath);
    });
  });

  group('while signed in', () {
    const state = AuthAuthenticated(identity);

    test('every application route is allowed', () {
      for (final location in [
        AppRoutes.dashboardPath,
        AppRoutes.rulesPath,
        AppRoutes.historyPath,
        AppRoutes.privacyPath,
        AppRoutes.profilePath,
      ]) {
        expect(resolve(state, location), isNull, reason: location);
      }
    });

    test('the authentication screens and splash are left behind', () {
      expect(resolve(state, AppRoutes.signInPath), AppRoutes.dashboardPath);
      expect(
        resolve(state, AppRoutes.createAccountPath),
        AppRoutes.dashboardPath,
      );
      expect(resolve(state, AppRoutes.splashPath), AppRoutes.dashboardPath);
    });

    test(
      'an unknown route is not rewritten, so the not-found screen shows',
      () {
        expect(resolve(state, '/does-not-exist'), isNull);
      },
    );

    test('signing out does not redirect mid-flight (no flicker)', () {
      const signingOut = AuthSigningOut(identity);

      expect(resolve(signingOut, AppRoutes.dashboardPath), isNull);
      expect(resolve(signingOut, AppRoutes.profilePath), isNull);
    });
  });
}
