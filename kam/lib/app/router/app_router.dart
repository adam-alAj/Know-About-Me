import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/profile_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/privacy/presentation/privacy_screen.dart';
import '../../features/rules/presentation/rules_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'unknown_route_screen.dart';

/// Builds the application router.
///
/// The shell hosts the primary destinations as branches so each keeps its own
/// navigation state. Authentication-aware navigation is supported by passing a
/// [redirect]: Phase 3 supplies a guard here without restructuring any route.
///
/// ```text
/// Authentication → Onboarding → Pairing → Main shell
///                                            ├── Reassurance
///                                            ├── Rules
///                                            ├── History
///                                            └── Privacy
/// ```
GoRouter createAppRouter({
  String initialLocation = AppRoutes.dashboardPath,
  GoRouterRedirect? redirect,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: redirect,
    routes: <RouteBase>[
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
      // Phase 3 registers sign-in and pairing routes here, behind the redirect
      // guard. They are declared in AppRoutes already so guards can reference
      // them without string literals.
    ],
    errorBuilder: (context, state) =>
        UnknownRouteScreen(uri: state.uri.toString()),
  );
}
