import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/error_view.dart';
import '../../../core/ui/widgets/loading_view.dart';
import '../domain/models/auth_state.dart';
import 'providers/auth_providers.dart';

/// Startup state while the authentication state is being determined.
///
/// The router sends every location here while `AuthInitializing`, which is what
/// guarantees protected content is never shown before authorization is known
/// (SRS Task 21). It also renders the failure when authentication state itself
/// cannot be determined, so the app cannot fail into a permanent spinner.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState case AuthError(:final failure)) {
      return AppScaffold(
        title: 'Know About Me',
        body: ErrorView(
          title: 'Cannot start right now',
          message: failure.message,
          retryLabel: 'Try again',
          onRetry: () => ref.read(authStateProvider.notifier).retry(),
        ),
      );
    }

    return const AppScaffold(
      title: 'Know About Me',
      body: LoadingView(label: 'Checking your session'),
    );
  }
}
