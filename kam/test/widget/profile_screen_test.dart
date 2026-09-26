import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';

import '../fakes/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('shows the signed-out state with the default repository', (
    tester,
  ) async {
    await pumpTestApp(tester, initialLocation: '/profile');

    expect(find.text('Not signed in'), findsOneWidget);
  });

  testWidgets('renders a user supplied by a fake repository', (tester) async {
    await pumpTestApp(
      tester,
      initialLocation: '/profile',
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            user: const AppUser(id: 'user-a', displayName: 'Afraa'),
          ),
        ),
      ],
    );

    expect(find.text('Afraa'), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);
  });

  testWidgets('renders a failure without leaking internals', (tester) async {
    await pumpTestApp(
      tester,
      initialLocation: '/profile',
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            failure: const RemoteServiceFailure(
              'Account service is unavailable',
              cause: 'SQLSTATE 42P01 secret',
            ),
          ),
        ),
      ],
    );

    expect(find.text('Could not load your account'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });
}
