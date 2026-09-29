import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/providers.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/storage/sensitive_local_data.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_profile_repository.dart';
import '../fakes/recording_logger.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Records how often protected local state is cleared.
class _RecordingSensitiveLocalData implements SensitiveLocalData {
  int clearCount = 0;

  @override
  Future<void> clear() async => clearCount++;
}

/// Phase 19: session end must drop protected local state.
///
/// A session can end because the user signed out *or* because the token was
/// revoked/expired elsewhere. Both paths must clear the cached location,
/// activity and history (SRS NFR-004).
void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late RecordingLogger logger;
  late _RecordingSensitiveLocalData localData;
  late ProviderContainer container;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profiles),
      loggerProvider.overrideWithValue(logger),
      sensitiveLocalDataProvider.overrideWithValue(localData),
    ],
  );

  setUp(() {
    profiles = FakeProfileRepository();
    logger = RecordingLogger();
    localData = _RecordingSensitiveLocalData();
  });

  tearDown(() {
    container.dispose();
    auth.dispose();
  });

  test('an explicit sign-out clears protected local state', () async {
    auth = FakeAuthRepository(
      initialIdentity: const AuthIdentity(uid: 'user-a'),
    );
    container = buildContainer();
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    await settle();

    expect(localData.clearCount, 0);

    final result = await container.read(authStateProvider.notifier).signOut();
    await settle();

    expect(result.isSuccess, isTrue);
    expect(localData.clearCount, 1);
  });

  test('a session revoked elsewhere clears protected local state', () async {
    auth = FakeAuthRepository(
      initialIdentity: const AuthIdentity(uid: 'user-a'),
    );
    container = buildContainer();
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    await settle();

    auth.simulateExternalSignOut();
    await settle();

    expect(localData.clearCount, 1);
  });

  test('a failed sign-out keeps the session and its local state', () async {
    auth = FakeAuthRepository(
      initialIdentity: const AuthIdentity(uid: 'user-a'),
      signOutFailure: const RemoteServiceFailure('Backend unavailable'),
    );
    container = buildContainer();
    container.listen(authStateProvider, (_, _) {}, fireImmediately: true);
    await settle();

    final result = await container.read(authStateProvider.notifier).signOut();
    await settle();

    expect(result.isFailure, isTrue);
    expect(localData.clearCount, 0);
  });
}
