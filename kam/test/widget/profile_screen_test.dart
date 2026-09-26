import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';

import '../fakes/fake_profile_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('shows the stored profile and the sign-in email', (tester) async {
    await pumpTestApp(
      tester,
      profileRepository: FakeProfileRepository(
        profile: const AppUser(id: 'user-a', displayName: 'Afraa'),
      ),
    );

    await openProfile(tester);

    expect(find.text('Afraa'), findsOneWidget);
    expect(find.text('afraa@example.com'), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);
  });

  testWidgets('offers to finish setting up when no profile exists', (
    tester,
  ) async {
    await pumpTestApp(tester, withProfile: false);
    await openProfile(tester);

    // The account exists, the profile does not: stated plainly rather than
    // filled with invented data (FR-048, Task 14).
    expect(find.text('Your profile is not set up yet'), findsOneWidget);
    expect(find.text('Finish setup'), findsOneWidget);
    expect(find.text('Afraa'), findsNothing);
    expect(find.text('admin'), findsNothing);
  });

  testWidgets('reports a failed profile read without leaking internals', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      profileRepository: FakeProfileRepository(
        readFailure: const RemoteServiceFailure(
          'Profile service is unavailable',
          cause: 'SQLSTATE 42P01 secret',
        ),
      ),
    );

    await openProfile(tester);

    expect(find.text('Profile service is unavailable'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('42P01'), findsNothing);
  });

  testWidgets('creates the profile when the user completes setup', (
    tester,
  ) async {
    final profiles = FakeProfileRepository();

    await pumpTestApp(tester, withProfile: false, profileRepository: profiles);

    await openProfile(tester);

    await tester.enterText(find.byType(TextField), 'Afraa');
    await scrollAndTap(tester, find.text('Finish setup'));

    expect(profiles.createCallCount, 1);
    expect(profiles.profile?.displayName, 'Afraa');
    // The screen reloads from the repository rather than trusting the form.
    expect(find.text('Save name'), findsOneWidget);
  });

  testWidgets('shows a validation message for an empty display name', (
    tester,
  ) async {
    final profiles = FakeProfileRepository();

    await pumpTestApp(tester, withProfile: false, profileRepository: profiles);

    await openProfile(tester);

    await scrollAndTap(tester, find.text('Finish setup'));

    expect(find.text('Enter a name to display.'), findsOneWidget);
    expect(profiles.createCallCount, 0);
  });

  testWidgets('updates the display name of an existing profile', (
    tester,
  ) async {
    final profiles = FakeProfileRepository(
      profile: const AppUser(id: 'user-a', displayName: 'Afraa'),
    );

    await pumpTestApp(tester, profileRepository: profiles);

    await openProfile(tester);

    await tester.enterText(find.byType(TextField), 'Afraa B');
    await scrollAndTap(tester, find.text('Save name'));

    expect(profiles.updateCallCount, 1);
    expect(profiles.createCallCount, 0);
    expect(profiles.profile?.displayName, 'Afraa B');
  });

  testWidgets('reports a failed profile save without leaking internals', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      profileRepository: FakeProfileRepository(
        profile: const AppUser(id: 'user-a', displayName: 'Afraa'),
        updateFailure: const PermissionFailure(
          'You do not have access to this information.',
          cause: 'rules_version = secret',
        ),
      ),
    );

    await openProfile(tester);

    await tester.enterText(find.byType(TextField), 'Afraa B');
    await scrollAndTap(tester, find.text('Save name'));

    expect(
      find.text('You do not have access to this information.'),
      findsOneWidget,
    );
    expect(find.textContaining('rules_version'), findsNothing);
  });

  testWidgets('signing out returns to the sign-in screen', (tester) async {
    await pumpTestApp(tester);
    await openProfile(tester);

    await scrollAndTap(tester, find.text('Sign out'));

    // The guard, not the button, is what moves the user (SRS Task 7).
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Afraa'), findsNothing);
  });
}
