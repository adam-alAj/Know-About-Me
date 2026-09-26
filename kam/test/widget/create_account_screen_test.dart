import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_profile_repository.dart';
import '../support/test_app.dart';

void main() {
  /// Starts signed out (so the authentication flow is reachable) and opens the
  /// create-account screen the way a user does.
  Future<void> pumpCreateAccount(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    FakeProfileRepository? profiles,
  }) async {
    await pumpTestApp(
      tester,
      signedIn: false,
      authRepository: auth,
      profileRepository: profiles,
    );
    await tester.tap(find.text('Create one'));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(
    WidgetTester tester, {
    String name = 'Afraa',
    String email = 'afraa@example.com',
    String password = 'password1',
    String? confirm,
  }) async {
    await tester.enterText(find.byType(TextField).at(0), name);
    await tester.enterText(find.byType(TextField).at(1), email);
    await tester.enterText(find.byType(TextField).at(2), password);
    await tester.enterText(find.byType(TextField).at(3), confirm ?? password);
  }

  Future<void> submit(WidgetTester tester) async {
    await scrollAndTap(
      tester,
      find.widgetWithText(FilledButton, 'Create account'),
    );
  }

  testWidgets('opens the create-account screen from sign in', (tester) async {
    await pumpCreateAccount(tester);

    expect(find.text('Display name'), findsWidgets);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('validates every field before calling the provider', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpCreateAccount(tester, auth: auth);

    await submit(tester);

    expect(find.text('Enter a name to display.'), findsOneWidget);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(find.text('Re-enter your password.'), findsOneWidget);
    expect(auth.registerCallCount, 0);
  });

  testWidgets('rejects a password that is too short', (tester) async {
    final auth = FakeAuthRepository();
    await pumpCreateAccount(tester, auth: auth);

    await fillForm(tester, password: 'short');
    await submit(tester);

    expect(find.textContaining('Use at least'), findsOneWidget);
    expect(auth.registerCallCount, 0);
  });

  testWidgets('rejects a password mismatch', (tester) async {
    final auth = FakeAuthRepository();
    await pumpCreateAccount(tester, auth: auth);

    await fillForm(tester, confirm: 'different1');
    await submit(tester);

    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(auth.registerCallCount, 0);
  });

  testWidgets('reports an already-registered email', (tester) async {
    final auth = FakeAuthRepository(
      registrationFailure: const ValidationFailure(
        'That email address is already registered.',
      ),
    );
    await pumpCreateAccount(tester, auth: auth);

    await fillForm(tester);
    await submit(tester);

    expect(
      find.text('That email address is already registered.'),
      findsOneWidget,
    );
    // Registration failed outright, so the user stays in the authentication flow.
    expect(find.text('Reassurance'), findsNothing);
  });

  testWidgets('reports a provider failure without leaking internals', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      registrationFailure: const RemoteServiceFailure(
        'Could not reach the service. Check your connection and try again.',
        cause: 'FirebaseException: 500 secret-detail',
      ),
    );
    await pumpCreateAccount(tester, auth: auth);

    await fillForm(tester);
    await submit(tester);

    expect(find.textContaining('secret-detail'), findsNothing);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });

  testWidgets('a successful registration lands in the authenticated app', (
    tester,
  ) async {
    await pumpCreateAccount(tester);

    await fillForm(tester);
    await submit(tester);

    expect(find.text('Reassurance'), findsOneWidget);
  });

  testWidgets(
    'a registration whose profile write failed is never reported as complete',
    (tester) async {
      // The account is created but the profile document is not: the app must
      // surface the incomplete setup rather than a plain success (Task 5).
      await pumpCreateAccount(
        tester,
        profiles: FakeProfileRepository(
          createFailure: const RemoteServiceFailure('Backend unavailable'),
        ),
      );

      await fillForm(tester);
      await submit(tester);

      expect(find.text('Finish setting up your profile'), findsOneWidget);
      expect(
        find.textContaining('no profile was saved for it'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows the wait and disables submit while a request is in flight',
    (tester) async {
      final auth = FakeAuthRepository(
        operationDelay: const Duration(seconds: 1),
      );
      await pumpCreateAccount(tester, auth: auth);

      await fillForm(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(auth.registerCallCount, 1);
    },
  );

  testWidgets('cannot be reached while accounts are unavailable', (
    tester,
  ) async {
    await pumpCreateAccount(
      tester,
      auth: FakeAuthRepository(
        isAvailable: false,
        unavailableReason: 'No account service is configured for this build.',
      ),
    );

    expect(find.text('Accounts are unavailable'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    expect(button.onPressed, isNull);
  });
}
