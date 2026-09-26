import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/core/ui/data_presentation_state.dart';
import 'package:kam/core/ui/presentation_mapping.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';

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
      'a stream error is reported as a failure rather than masked by loading',
      () async {
        // Riverpod 3 keeps the loading flag set while also recording the error,
        // so this is the case a naive `.when()` would hide.
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                failure: const RemoteServiceFailure(
                  'Account service is unavailable',
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(currentUserProvider, (_, _) {}, fireImmediately: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final presentation = PresentationMapping.fromAsync(
          container.read(currentUserProvider),
        );

        expect(presentation.state, DataPresentationState.failure);
        expect(presentation.message, 'Account service is unavailable');
      },
    );
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
          Failure<int>(UnsupportedCapabilityFailure('No screen state on iOS')),
        ),
      );

      expect(presentation.state, DataPresentationState.failure);
      expect(presentation.message, 'No screen state on iOS');
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
