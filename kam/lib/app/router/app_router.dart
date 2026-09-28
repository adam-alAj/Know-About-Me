import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/privacy/presentation/privacy_screen.dart';
import '../../features/pairing/presentation/pairing_screen.dart';
import '../../features/rules/presentation/rule_builder_screen.dart';
import '../../features/rules/presentation/rules_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'auth_redirect.dart';
import 'unknown_route_screen.dart';

/// Builds the application router.
///
/// The shell hosts the primary destinations as branches so each keeps its own
/// navigation state. Authentication-aware navigation is supplied through
/// [redirect] (a pure function from `AuthRedirect`) plus a [refreshListenable]
/// that fires whenever the authentication state changes.
///
/// ```text
/// Splash → Sign in / Create account        (unauthenticated)
///        → Reassurance shell                (authenticated)
///             ├── Reassurance
///             ├── Rules
///             ├── History
///             └── Privacy
///          └── Profile (above the shell)
/// ```
GoRouter createAppRouter({
  String initialLocation = AppRoutes.dashboardPath,
  GoRouterRedirect? redirect,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: redirect,
    refreshListenable: refreshListenable,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splashPath,
        name: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.signInPath,
        name: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.createAccountPath,
        name: AppRoutes.createAccount,
        builder: (context, state) => const CreateAccountScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboardPath,
                name: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.rulesPath,
                name: AppRoutes.rules,
                builder: (context, state) => const RulesScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'new',
                    name: AppRoutes.ruleCreate,
                    builder: (context, state) => const RuleBuilderScreen(),
                  ),
                  GoRoute(
                    path: ':ruleId/edit',
                    name: AppRoutes.ruleEdit,
                    builder: (context, state) => RuleBuilderScreen(
                      ruleId: state.pathParameters['ruleId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.historyPath,
                name: AppRoutes.history,
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.privacyPath,
                name: AppRoutes.privacy,
                builder: (context, state) => const PrivacyScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.profilePath,
        name: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(path: AppRoutes.pairingPath, name: AppRoutes.pairing,
        builder: (context, state) => const PairingScreen()),
    ],
    errorBuilder: (context, state) =>
        UnknownRouteScreen(uri: state.uri.toString()),
  );
}

/// The location the app starts at.
///
/// A provider so tests can start at a specific route without building their own
/// router — which keeps the real guard under test (SRS NFR-018).
final appInitialLocationProvider = Provider<String>(
  (ref) => AppRoutes.dashboardPath,
);

/// The application router, wired to the authentication guard and to
/// authentication-state changes.
///
/// Built inside a provider rather than a widget so the guard can read providers
/// directly and so the router exists exactly once per container.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthStateRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return createAppRouter(
    initialLocation: ref.read(appInitialLocationProvider),
    redirect: (context, state) => AuthRedirect.resolve(
      authState: ref.read(authStateProvider),
      location: state.uri.path,
    ),
    refreshListenable: refresh,
  );
});

/// Bridges Riverpod's authentication state to go_router's [Listenable], so a
/// sign-in or sign-out re-evaluates the redirect immediately.
class _AuthStateRefreshNotifier extends ChangeNotifier {
  _AuthStateRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (previous, next) {
      if (previous != next) notifyListeners();
    });
  }
}
