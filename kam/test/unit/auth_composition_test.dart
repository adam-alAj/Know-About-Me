import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/providers.dart';
import 'package:kam/core/config/app_config.dart';
import 'package:kam/core/config/app_environment.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/firebase/firebase_bootstrap.dart';
import 'package:kam/features/auth/domain/models/auth_state.dart';
import 'package:kam/features/auth/domain/services/auth_service.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/recording_logger.dart';

/// Proves the behaviour of the **default** composition — the one a build with no
/// Firebase configuration actually runs, which is what this repository ships.
///
/// Only the configuration and the logger are overridden: the auth repository,
/// profile repository, service and controller are the real ones. The point is
/// that the app states the truth about its own capability instead of offering a
/// sign-in form that cannot work (SRS constraint 10), and that no code path
/// fabricates an account.
void main() {
  const config = AppConfig(
    environment: AppEnvironment.development,
    enableVerboseLogging: false,
  );

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      loggerProvider.overrideWithValue(RecordingLogger()),
    ],
  );

  tearDown(FirebaseBootstrap.reset);

  test('an unconfigured build reports accounts as unavailable', () {
    final container = buildContainer();
    addTearDown(container.dispose);

    expect(FirebaseBootstrap.isInitialized, isFalse);
    expect(container.read(authAvailableProvider), isFalse);
    // The reason is user-safe: no configuration internals, no identifiers.
    final reason = container.read(authUnavailableReasonProvider);
    expect(reason, isNotNull);
    expect(reason, contains('no account service is configured'));
  });

  test('it still reports the truth about the signed-in state', () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    expect(container.read(authStateProvider), isA<AuthInitializing>());

    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Nobody is signed in — which is true, and is not "signed out because the
    // service is broken".
    expect(container.read(authStateProvider), isA<AuthUnauthenticated>());
  });

  test('credential operations fail with a configuration failure', () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final service = container.read(authServiceProvider);

    final signIn = await service.signIn(
      email: 'afraa@example.com',
      password: 'password1',
    );
    expect(signIn.failureOrNull, isA<ConfigurationFailure>());

    // Registration is rejected before an account could be claimed to exist.
    final registration = await service.register(
      email: 'afraa@example.com',
      password: 'password1',
      confirmPassword: 'password1',
      displayName: 'Afraa',
    );
    expect(registration, isA<RegistrationRejected>());
  });

  test(
    'the profile read reports no profile rather than inventing one',
    () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final profile = await container
          .read(profileRepositoryProvider)
          .getProfile('user-a');

      expect(profile.isSuccess, isTrue);
      expect(profile.valueOrNull, isNull);
    },
  );

  test('writing a profile fails rather than pretending to save', () async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final written = await container
        .read(profileRepositoryProvider)
        .createProfile(uid: 'user-a', displayName: 'Afraa');

    expect(written.failureOrNull, isA<ConfigurationFailure>());
  });
}
