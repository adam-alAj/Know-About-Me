import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/providers.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/domain/models/auth_state.dart';
import 'package:kam/features/auth/domain/services/auth_service.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_profile_repository.dart';
import '../fakes/recording_logger.dart';

/// Lets the identity stream and the profile read settle.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late ProviderContainer container;
  late RecordingLogger logger;

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        // The logger always carries the real provider override, so these tests
        // never read the compiler environment.
        loggerProvider.overrideWithValue(logger),
      ],
    );
  }

  tearDown(() {
    container.dispose();
    auth.dispose();
  });

  group('startup and restoration (SRS Task 8, Task 24)', () {
    test('starts initializing, then resolves to unauthenticated', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();

      expect(container.read(authStateProvider), isA<AuthInitializing>());

      await settle();

      expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
    });

    test('an existing session is restored without user action', () async {
      auth = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'user-a',
          email: 'afraa@example.com',
        ),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();

      container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
      await settle();

      final state = container.read(authStateProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(state.identity?.uid, 'user-a');
    });
  });

  group('sign in', () {
    test('moves to authenticated and returns the identity', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();

      final result = await container
          .read(authStateProvider.notifier)
          .signIn(email: 'afraa@example.com', password: 'password1');
      await settle();

      expect(result, isA<Success<AuthIdentity>>());
      expect(container.read(authStateProvider), isA<AuthAuthenticated>());
      expect(auth.signInCallCount, 1);
    });

    test('restores the signed-out state and reports why', () async {
      auth = FakeAuthRepository(
        signInFailure: const AuthenticationFailure(
          'The email or password is incorrect.',
        ),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      await settle();

      final result = await container
          .read(authStateProvider.notifier)
          .signIn(email: 'afraa@example.com', password: 'password1');

      expect(
        result.failureOrNull?.message,
        'The email or password is incorrect.',
      );
      // Never left "authenticating" with nothing in flight.
      expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
      expect(
        logger.entries.any(
          (e) => e.message.contains('Authentication operation failed'),
        ),
        isTrue,
      );
    });

    test('a second request while one is in flight is refused', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();

      final notifier = container.read(authStateProvider.notifier);
      final first = notifier.signIn(
        email: 'afraa@example.com',
        password: 'password1',
      );
      final second = notifier.signIn(
        email: 'afraa@example.com',
        password: 'password1',
      );

      await Future.wait([first, second]);

      expect(auth.signInCallCount, 1);
    });
  });

  group('register (SRS Task 4, Task 5)', () {
    test('completes and becomes authenticated', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();

      final result = await container
          .read(authStateProvider.notifier)
          .register(
            email: 'afraa@example.com',
            password: 'password1',
            confirmPassword: 'password1',
            displayName: 'Afraa',
          );
      await settle();

      expect(result, isA<RegistrationComplete>());
      expect(container.read(authStateProvider), isA<AuthAuthenticated>());
    });

    test('a rejected registration leaves the user signed out', () async {
      auth = FakeAuthRepository(
        registrationFailure: const ValidationFailure(
          'That email address is already registered.',
        ),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      await settle();

      final result = await container
          .read(authStateProvider.notifier)
          .register(
            email: 'afraa@example.com',
            password: 'password1',
            confirmPassword: 'password1',
            displayName: 'Afraa',
          );

      expect(result, isA<RegistrationRejected>());
      expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
    });

    test(
      'a pending profile keeps the session and stays non-successful',
      () async {
        auth = FakeAuthRepository();
        profiles = FakeProfileRepository(
          createFailure: const RemoteServiceFailure('Backend unavailable'),
        );
        logger = RecordingLogger();
        container = buildContainer();
        // Subscribed before registering so the profile read is observed once the
        // identity appears.
        container.listen(
          currentUserProfileProvider,
          (_, _) {},
          fireImmediately: true,
        );

        final result = await container
            .read(authStateProvider.notifier)
            .register(
              email: 'afraa@example.com',
              password: 'password1',
              confirmPassword: 'password1',
              displayName: 'Afraa',
            );
        await settle();

        expect(result, isA<RegistrationProfilePending>());
        // The account exists, so the user stays signed in and is routed to the
        // recovery path rather than losing the session.
        expect(container.read(authStateProvider), isA<AuthAuthenticated>());

        final profile = container.read(currentUserProfileProvider);
        expect(profile.hasValue, isTrue);
        expect(profile.requireValue.valueOrNull, isNull);
      },
    );
  });

  group('sign out (SRS Task 7)', () {
    test('clears the session and drops cached profile data', () async {
      auth = FakeAuthRepository(
        initialIdentity: const AuthIdentity(uid: 'user-a'),
      );
      profiles = FakeProfileRepository(
        profile: const AppUser(id: 'user-a', displayName: 'Afraa'),
      );
      logger = RecordingLogger();
      container = buildContainer();
      container.listen(
        currentUserProfileProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await settle();

      expect(
        container.read(currentUserProfileProvider).requireValue.valueOrNull,
        isNotNull,
      );

      final result = await container.read(authStateProvider.notifier).signOut();
      await settle();

      expect(result.isSuccess, isTrue);
      expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
      // No authenticated data survives the sign-out.
      expect(
        container.read(currentUserProfileProvider).requireValue.valueOrNull,
        isNull,
      );
      expect(auth.signOutCallCount, 1);
    });

    test('a failed sign-out leaves the user signed in', () async {
      auth = FakeAuthRepository(
        initialIdentity: const AuthIdentity(uid: 'user-a'),
        signOutFailure: const RemoteServiceFailure('Backend unavailable'),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
      await settle();

      final result = await container.read(authStateProvider.notifier).signOut();

      expect(result.isFailure, isTrue);
      // The provider still holds the session, so the app must not pretend the
      // user is signed out.
      expect(container.read(authStateProvider), isA<AuthAuthenticated>());
    });

    test('signing out while signed out is a no-op', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      await settle();

      final result = await container.read(authStateProvider.notifier).signOut();

      expect(result.isSuccess, isTrue);
      expect(auth.signOutCallCount, 0);
    });
  });

  group('external state changes (SRS Task 10)', () {
    test('a session revoked elsewhere signs the user out', () async {
      auth = FakeAuthRepository(
        initialIdentity: const AuthIdentity(uid: 'user-a'),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
      await settle();

      auth.simulateExternalSignOut();
      await settle();

      expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
    });

    test('a stream failure is reported as unknown, not as signed out', () async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
      await settle();

      auth.simulateStreamError(
        const RemoteServiceFailure('Account service is unavailable'),
      );
      await settle();

      // "Unknown" is not "signed out": presenting a sign-in form here would hide
      // an outage.
      final state = container.read(authStateProvider);
      expect(state, isA<AuthError>());
      expect(
        (state as AuthError).failure.message,
        'Account service is unavailable',
      );
    });

    test('retry re-runs initialization', () async {
      auth = FakeAuthRepository(
        initialIdentity: const AuthIdentity(uid: 'user-a'),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();
      container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
      await settle();

      auth.simulateStreamError(const RemoteServiceFailure('Down'));
      await settle();
      expect(container.read(authStateProvider), isA<AuthError>());

      container.read(authStateProvider.notifier).retry();
      await settle();

      expect(container.read(authStateProvider), isA<AuthAuthenticated>());
    });
  });

  group('logging (constraint 7)', () {
    test('never logs credentials or email addresses', () async {
      auth = FakeAuthRepository(
        signInFailure: const AuthenticationFailure('Wrong credentials'),
      );
      profiles = FakeProfileRepository();
      logger = RecordingLogger();
      container = buildContainer();

      await container
          .read(authStateProvider.notifier)
          .signIn(email: 'afraa@example.com', password: 'super-secret-1');

      final logged = logger.entries
          .map((e) => '${e.message} ${e.context}')
          .join(' ');
      expect(logged, isNot(contains('super-secret-1')));
      expect(logged, isNot(contains('afraa@example.com')));
    });
  });
}
