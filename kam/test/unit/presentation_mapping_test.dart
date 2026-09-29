import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/core/ui/data_presentation_state.dart';
import 'package:kam/core/ui/presentation_mapping.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_profile_repository.dart';

void main() {
  group('PresentationMapping.fromAsync', () {
    test('maps data to loaded', () {
      final presentation = PresentationMapping.fromAsync(
        const AsyncData<String>('value'),
      );

      expect(presentation.state, DataPresentationState.loaded);
    });

    test('maps errors to failure with a safe message', () {
      final presentation = PresentationMapping.fromAsync(
        AsyncError<String>(
          const PermissionFailure('Location permission is required'),
          StackTrace.empty,
        ),
      );

      expect(presentation.state, DataPresentationState.failure);
      expect(presentation.message, 'Location permission is required');
    });

    test('maps an in-progress read to loading', () {
      expect(
        PresentationMapping.fromAsync(const AsyncLoading<String>()).state,
        DataPresentationState.loading,
      );
    });

    test(
      'a failing read is reported as a failure rather than masked by loading',
      () async {
        // Riverpod 3 keeps the loading flag set while also recording the error,
        // so this is the case a naive `.when()` would hide.
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                initialIdentity: const AuthIdentity(uid: 'user-a'),
              ),
            ),
            profileRepositoryProvider.overrideWithValue(
              FakeProfileRepository(
                readFailure: const RemoteServiceFailure(
                  'Account service is unavailable',
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          currentUserProfileProvider,
          (_, _) {},
          fireImmediately: true,
        );
        try {
          await container.read(userProfileProvider('user-a').future);
        } catch (_) {
          // Wait for the provider's actual failure rather than guessing at a
          // fixed scheduling delay.
        }

        final presentation = PresentationMapping.fromAsyncNullableResult(
          container.read(currentUserProfileProvider),
        );

        expect(presentation.state, DataPresentationState.failure);
        expect(presentation.message, 'Account service is unavailable');
      },
    );
  });

  group('PresentationMapping.fromAsyncNullableResult', () {
    test('maps a present value to loaded', () {
      final presentation = PresentationMapping.fromAsyncNullableResult(
        const AsyncData<Result<String?>>(Success<String?>('value')),
      );

      expect(presentation.state, DataPresentationState.loaded);
    });

    test('maps a successful null to empty rather than loaded', () {
      // The read worked and there genuinely is nothing: rendering this as
      // content would invent a value the system does not have (FR-048).
      final presentation = PresentationMapping.fromAsyncNullableResult(
        const AsyncData<Result<String?>>(Success<String?>(null)),
      );

      expect(presentation.state, DataPresentationState.empty);
    });

    test('maps a failed result to failure', () {
      final presentation = PresentationMapping.fromAsyncNullableResult(
        const AsyncData<Result<String?>>(
          Failure<String?>(NotFoundFailure('No profile yet')),
        ),
      );

      expect(presentation.state, DataPresentationState.failure);
      expect(presentation.message, 'No profile yet');
    });

    test('maps an in-progress read to loading', () {
      expect(
        PresentationMapping.fromAsyncNullableResult(
          const AsyncLoading<Result<String?>>(),
        ).state,
        DataPresentationState.loading,
      );
    });
  });

  group('PresentationMapping.fromAsyncResult', () {
    test('maps a successful result to loaded', () {
      final presentation = PresentationMapping.fromAsyncResult(
        const AsyncData<Result<int>>(Success<int>(42)),
      );

      expect(presentation.state, DataPresentationState.loaded);
    });

    test('maps a failed result to failure', () {
      final presentation = PresentationMapping.fromAsyncResult(
        const AsyncData<Result<int>>(
          Failure<int>(
            UnsupportedCapabilityFailure(
              'Screen state is unsupported on this target.',
            ),
          ),
        ),
      );

      expect(presentation.state, DataPresentationState.failure);
      expect(
        presentation.message,
        'Screen state is unsupported on this target.',
      );
    });

    test('maps a thrown error to failure', () {
      final presentation = PresentationMapping.fromAsyncResult(
        AsyncError<Result<int>>(StateError('boom'), StackTrace.empty),
      );

      expect(presentation.state, DataPresentationState.failure);
      // Internals are not leaked.
      expect(presentation.message, isNot(contains('boom')));
    });

    test('maps a pending read to loading', () {
      expect(
        PresentationMapping.fromAsyncResult(
          const AsyncLoading<Result<int>>(),
        ).state,
        DataPresentationState.loading,
      );
    });
  });
}
