import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exposed from the misc library in Riverpod 3.x.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/app.dart';
import 'package:kam/app/providers.dart';
import 'package:kam/app/router/app_router.dart';
import 'package:kam/app/router/app_routes.dart';
import 'package:kam/core/config/app_config.dart';
import 'package:kam/core/config/app_environment.dart';
import 'package:kam/core/time/clock.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_profile_repository.dart';

/// Deterministic configuration used by every widget test.
const AppConfig testConfig = AppConfig(
  environment: AppEnvironment.development,
  enableVerboseLogging: true,
);

/// The identity every test starts from unless it says otherwise.
const AuthIdentity testIdentity = AuthIdentity(
  uid: 'user-a',
  email: 'afraa@example.com',
);

/// The profile document every test starts from unless it says otherwise.
const AppUser testProfile = AppUser(id: 'user-a', displayName: 'Afraa');

/// An override that pins the clock to [now], making freshness deterministic.
Override fixedClock(DateTime now) =>
    clockProvider.overrideWithValue(FixedClock(now));

/// Pumps the real root widget with test overrides, including the **real**
/// authentication guard and router.
///
/// The router is not built here: it comes from `appRouterProvider`, so widget
/// tests exercise the same redirect logic the app uses. [initialLocation] only
/// changes where the app *attempts* to start, which is exactly what a deep link
/// does — so "protected route" tests are meaningful rather than tautological.
///
/// Returns the fakes so a test can assert on calls or change state mid-test.
Future<void> pumpTestApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  String initialLocation = AppRoutes.dashboardPath,
  bool signedIn = true,
  bool withProfile = true,
  bool settle = true,
  FakeAuthRepository? authRepository,
  FakeProfileRepository? profileRepository,
}) async {
  // A replacement repository is supplied as a typed parameter rather than as an
  // extra `Override`, because Riverpod 3 refuses to override the same provider
  // twice in one container.
  final auth =
      authRepository ??
      FakeAuthRepository(initialIdentity: signedIn ? testIdentity : null);
  final profiles =
      profileRepository ??
      FakeProfileRepository(
        profile: signedIn && withProfile ? testProfile : null,
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(testConfig),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        appInitialLocationProvider.overrideWithValue(initialLocation),
        ...overrides,
      ],
      child: const KamApp(config: testConfig),
    ),
  );
  // `pumpAndSettle` also flushes the identity stream and the profile read, so
  // the guard has resolved before assertions run. Pass `settle: false` to
  // inspect the very first frame, which is the splash screen.
  if (settle) await tester.pumpAndSettle();
}

/// Navigates to the profile screen the way a user does.
///
/// Tests reach a protected screen by navigating rather than by deep-linking a
/// cold start: while the authentication state is still unknown the guard sends
/// protected locations to the splash screen, so a cold-start deep link would be
/// replaced. Reaching the screen through the UI is both closer to real use and
/// independent of that timing (see the known limitation in
/// `docs/PHASE_04_COMPLETION_REPORT.md`).
Future<void> openProfile(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.person_outline));
  await tester.pumpAndSettle();
}

/// Brings [finder] into view inside the page's list, then taps it.
///
/// A `ListView` only builds the children it is showing, so an action near the
/// bottom of a long page neither exists nor can be tapped until it is scrolled
/// to. Without this, a tap would silently miss and the test would assert on a
/// screen that never changed.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
