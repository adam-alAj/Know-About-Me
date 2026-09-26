import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/domain/services/auth_service.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_profile_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;

  AuthService buildService() => AuthService(auth: auth, profiles: profiles);

  tearDown(() => auth.dispose());

  group('register', () {
    test('rejects invalid input before touching the provider', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();

      final result = await buildService().register(
        email: 'not-an-email',
        password: 'password1',
        confirmPassword: 'password1',
        displayName: 'Afraa',
      );

      expect(result, isA<RegistrationRejected>());
      expect(
        (result as RegistrationRejected).failure,
        isA<ValidationFailure>(),
      );
      // Nothing was created, so a retry is safe.
      expect(auth.registerCallCount, 0);
      expect(profiles.createCallCount, 0);
    });

    test('rejects a password mismatch before touching the provider', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();

      final result = await buildService().register(
        email: 'afraa@example.com',
        password: 'password1',
        confirmPassword: 'password2',
        displayName: 'Afraa',
      );

      expect(result, isA<RegistrationRejected>());
      expect(auth.registerCallCount, 0);
    });

    test('creates the account and its profile', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();

      final result = await buildService().register(
        email: 'afraa@example.com',
        password: 'password1',
        confirmPassword: 'password1',
        displayName: '  Afraa  ',
      );

      expect(result, isA<RegistrationComplete>());
      final complete = result as RegistrationComplete;
      expect(complete.identity.uid, 'user-new');
      expect(complete.profile.id, 'user-new');
      // The stored name is trimmed, so the client and the Rules agree.
      expect(complete.profile.displayName, 'Afraa');
    });

    test('reports a rejected account without claiming a profile', () async {
      auth = FakeAuthRepository(
        registrationFailure: const ValidationFailure(
          'That email address is already registered.',
        ),
      );
      profiles = FakeProfileRepository();

      final result = await buildService().register(
        email: 'afraa@example.com',
        password: 'password1',
        confirmPassword: 'password1',
        displayName: 'Afraa',
      );

      expect(result, isA<RegistrationRejected>());
      expect(profiles.createCallCount, 0);
    });

    test(
      'reports a pending profile instead of a success when the profile write fails',
      () async {
        auth = FakeAuthRepository();
        profiles = FakeProfileRepository(
          createFailure: const PermissionFailure(
            'You do not have access to this information.',
          ),
        );

        final result = await buildService().register(
          email: 'afraa@example.com',
          password: 'password1',
          confirmPassword: 'password1',
          displayName: 'Afraa',
        );

        // This is the SRS Task 5 requirement: registration must not be reported
        // as successful when the profile was not stored.
        expect(result, isA<RegistrationProfilePending>());
        final pending = result as RegistrationProfilePending;
        expect(pending.identity.uid, 'user-new');
        expect(pending.failure, isA<PermissionFailure>());
      },
    );

    test(
      'retrying after a partial failure does not duplicate or overwrite',
      () async {
        auth = FakeAuthRepository();
        profiles = FakeProfileRepository(
          createFailure: const RemoteServiceFailure('Backend unavailable'),
        );

        final service = buildService();
        await service.register(
          email: 'afraa@example.com',
          password: 'password1',
          confirmPassword: 'password1',
          displayName: 'Afraa',
        );

        // The backend recovers; the retry stores the profile and succeeds.
        profiles.createFailure = null;
        final retry = await service.register(
          email: 'afraa@example.com',
          password: 'password1',
          confirmPassword: 'password1',
          displayName: 'Afraa',
        );

        expect(retry, isA<RegistrationComplete>());
        expect(profiles.createCallCount, 2);

        // A third attempt (the user already has a profile) must not overwrite it.
        profiles.profile = profiles.profile!.copyWith(
          displayName: 'Edited later',
        );
        await service.register(
          email: 'afraa@example.com',
          password: 'password1',
          confirmPassword: 'password1',
          displayName: 'Afraa',
        );

        expect(profiles.profile?.displayName, 'Edited later');
      },
    );
  });

  group('signIn', () {
    test('validates before calling the provider', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();

      final result = await buildService().signIn(email: '', password: '');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(auth.signInCallCount, 0);
    });

    test('returns the provider identity on success', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();

      final result = await buildService().signIn(
        email: '  afraa@example.com ',
        password: 'password1',
      );

      expect(result.valueOrNull?.uid, 'user-a');
      // The address is trimmed before it reaches the provider.
      expect(result.valueOrNull?.email, 'afraa@example.com');
    });

    test('surfaces the mapped provider failure', () async {
      auth = FakeAuthRepository(
        signInFailure: const AuthenticationFailure(
          'The email or password is incorrect.',
        ),
      );
      profiles = FakeProfileRepository();

      final result = await buildService().signIn(
        email: 'afraa@example.com',
        password: 'password1',
      );

      expect(
        result.failureOrNull?.message,
        'The email or password is incorrect.',
      );
    });
  });

  group('signOut and loadProfile', () {
    test('signing out does not delete the profile', () async {
      auth = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'user-a',
          email: 'afraa@example.com',
        ),
      );
      profiles = FakeProfileRepository();

      final result = await buildService().signOut();

      expect(result.isSuccess, isTrue);
      expect(auth.signOutCallCount, 1);
      expect(auth.signedInIdentity, isNull);
    });

    test(
      'a missing profile is reported as null, never as a default user',
      () async {
        auth = FakeAuthRepository();
        profiles = FakeProfileRepository();

        final result = await buildService().loadProfile('user-a');

        expect(result.isSuccess, isTrue);
        expect(result.valueOrNull, isNull);
      },
    );
  });

  group('availability', () {
    test('reports the provider capability', () {
      auth = FakeAuthRepository(isAvailable: false, unavailableReason: 'Nope');
      profiles = FakeProfileRepository();

      expect(buildService().isAvailable, isFalse);
    });
  });
}
