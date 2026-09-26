import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/router/app_routes.dart';
import 'package:kam/core/error/app_failure.dart';

import '../fakes/fake_auth_repository.dart';
import '../support/test_app.dart';

/// The full authentication lifecycle through the real router and the real guard
/// (SRS Task 10, Task 24).
///
/// These tests use the production `appRouterProvider`: nothing builds a test-only
/// router, so what they prove is what ships.
void main() {
  group('signed out', () {
    testWidgets('lands on the sign-in screen', (tester) async {
      await pumpTestApp(tester, signedIn: false);

      expect(find.text('Reassurance'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
    });

    testWidgets('a protected route cannot be opened by its path', (
      tester,
    ) async {
      await pumpTestApp(
        tester,
        signedIn: false,
        initialLocation: AppRoutes.rulesPath,
      );

      // Hiding the navigation bar is not what protects this route (Task 9).
      expect(find.text('No rules yet'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
    });

    testWidgets('the profile route is protected too', (tester) async {
      await pumpTestApp(
        tester,
        signedIn: false,
        initialLocation: AppRoutes.profilePath,
      );

      expect(find.text('Your profile'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
    });
  });

  group('signed in', () {
    testWidgets('starts on the dashboard', (tester) async {
      await pumpTestApp(tester);

      expect(find.text('Reassurance'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('the authentication screens are left behind', (tester) async {
      await pumpTestApp(tester, initialLocation: AppRoutes.signInPath);

      expect(find.text('Reassurance'), findsOneWidget);
    });
  });

  group('the very first frame', () {
    testWidgets('is the splash screen, never protected content', (
      tester,
    ) async {
      await pumpTestApp(tester, settle: false);

      expect(find.text('Checking your session'), findsOneWidget);
      expect(find.text('Reassurance'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.pumpAndSettle();

      // Once the session is known, the app appears without a restart.
      expect(find.text('Reassurance'), findsOneWidget);
    });

    testWidgets('reports an undeterminable session instead of spinning', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpTestApp(tester, authRepository: auth, settle: false);
      await tester.pumpAndSettle();

      auth.simulateStreamError(
        const RemoteServiceFailure('Account service is unavailable'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cannot start right now'), findsOneWidget);
      expect(find.text('Account service is unavailable'), findsOneWidget);
      // Never a fabricated signed-in state, and never a permanent spinner.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('the full lifecycle', () {
    testWidgets('signed out → sign in → signed in → sign out → signed out', (
      tester,
    ) async {
      await pumpTestApp(tester, signedIn: false);
      expect(find.text('Sign in'), findsWidgets);

      // 1. Sign in.
      await tester.enterText(find.byType(TextField).first, 'afraa@example.com');
      await tester.enterText(find.byType(TextField).last, 'password1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Reassurance'), findsOneWidget);

      // 2. Sign out from the profile screen.
      await openProfile(tester);
      expect(find.text('afraa@example.com'), findsOneWidget);

      await scrollAndTap(tester, find.text('Sign out'));

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Reassurance'), findsNothing);

      // 3. Protected routes are unreachable again.
      await pumpTestApp(
        tester,
        signedIn: false,
        initialLocation: AppRoutes.rulesPath,
      );
      expect(find.text('No rules yet'), findsNothing);
    });

    testWidgets('a session revoked elsewhere returns the user to sign in', (
      tester,
    ) async {
      final auth = FakeAuthRepository(initialIdentity: testIdentity);
      await pumpTestApp(tester, authRepository: auth);

      expect(find.text('Reassurance'), findsOneWidget);

      // The provider pushes the change; no user action is involved.
      auth.simulateExternalSignOut();
      await tester.pumpAndSettle();

      expect(find.text('Reassurance'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
    });

    testWidgets('signing in again after a sign-out works', (tester) async {
      await pumpTestApp(tester, signedIn: false);

      Future<void> signIn() async {
        await tester.enterText(
          find.byType(TextField).first,
          'afraa@example.com',
        );
        await tester.enterText(find.byType(TextField).last, 'password1');
        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pumpAndSettle();
      }

      await signIn();
      expect(find.text('Reassurance'), findsOneWidget);

      await openProfile(tester);
      await scrollAndTap(tester, find.text('Sign out'));
      expect(find.text('Reassurance'), findsNothing);

      await signIn();
      expect(find.text('Reassurance'), findsOneWidget);
    });

    testWidgets('an existing session survives a restart', (tester) async {
      // Two separate app launches with the same provider identity: the second
      // must not force the user back through sign-in (Task 8, Task 24).
      final auth = FakeAuthRepository(initialIdentity: testIdentity);

      await pumpTestApp(tester, authRepository: auth);
      expect(find.text('Reassurance'), findsOneWidget);

      await pumpTestApp(tester, authRepository: auth);
      expect(find.text('Reassurance'), findsOneWidget);
      expect(auth.signInCallCount, 0);
    });
  });
}
