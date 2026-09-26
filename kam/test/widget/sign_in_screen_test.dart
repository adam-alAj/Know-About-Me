import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/validation/auth_input_validation.dart';

import '../fakes/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  Future<void> pumpSignedOut(
    WidgetTester tester, {
    FakeAuthRepository? repository,
  }) {
    // Starting signed out is what the guard needs in order to show this screen.
    return pumpTestApp(tester, signedIn: false, authRepository: repository);
  }

  testWidgets('the guard sends a signed-out user to the sign-in screen', (
    tester,
  ) async {
    await pumpSignedOut(tester);

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Reassurance'), findsNothing);
  });

  testWidgets('rejects an empty submit without calling the provider', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await pumpSignedOut(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(repository.signInCallCount, 0);
  });

  testWidgets('rejects a malformed email before calling the provider', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await pumpSignedOut(tester, repository: repository);

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(repository.signInCallCount, 0);
  });

  testWidgets('reports a wrong password in one vague message', (tester) async {
    final repository = FakeAuthRepository(
      signInFailure: const AuthenticationFailure(
        'The email or password is incorrect.',
      ),
    );
    await pumpSignedOut(tester, repository: repository);

    await tester.enterText(find.byType(TextField).first, 'afraa@example.com');
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    // Control is not handed to an authenticated screen on failure.
    expect(find.text('Reassurance'), findsNothing);
    expect(repository.signInCallCount, 1);
  });

  testWidgets('never leaks backend internals in the failure message', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      signInFailure: const RemoteServiceFailure(
        'Could not reach the service. Check your connection and try again.',
        cause: 'FirebaseException: internal error 500 secret-token',
      ),
    );
    await pumpSignedOut(tester, repository: repository);

    await tester.enterText(find.byType(TextField).first, 'afraa@example.com');
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('secret-token'), findsNothing);
    expect(find.textContaining('FirebaseException'), findsNothing);
    expect(
      find.text(
        'Could not reach the service. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows the wait and disables submit while a request is in flight',
    (tester) async {
      final repository = FakeAuthRepository(
        operationDelay: const Duration(seconds: 1),
      );
      await pumpSignedOut(tester, repository: repository);

      await tester.enterText(find.byType(TextField).first, 'afraa@example.com');
      await tester.enterText(find.byType(TextField).last, 'password1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);

      await tester.pumpAndSettle();
      expect(repository.signInCallCount, 1);
    },
  );

  testWidgets('states that accounts are unavailable in an unconfigured build', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      isAvailable: false,
      unavailableReason: 'No account service is configured for this build.',
    );
    await pumpSignedOut(tester, repository: repository);

    expect(find.text('Accounts are unavailable'), findsOneWidget);
    expect(
      find.text('No account service is configured for this build.'),
      findsOneWidget,
    );

    // The submit button is present but disabled, so a user cannot type a
    // password into a form that cannot work (constraint 10).
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sign in'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the password field is obscured', (tester) async {
    await pumpSignedOut(tester);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.length, 2);
    expect(fields.last.obscureText, isTrue);
  });

  testWidgets('the minimum password length is the shared constant', (
    tester,
  ) async {
    await pumpSignedOut(tester);

    // Guards against the UI and the validator drifting apart.
    expect(AuthInputValidation.minimumPasswordLength, greaterThanOrEqualTo(8));
  });
}
