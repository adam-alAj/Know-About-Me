import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/models/app_user.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/section_header.dart';
import 'providers/auth_providers.dart';

/// Profile placeholder (SRS FR-002).
///
/// Deliberately built against [currentUserProvider] rather than a stub: the
/// screen already renders the signed-out state, so wiring Firebase Auth in a
/// later phase changes the repository, not this UI.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final config = ref.watch(appConfigProvider);

    return AppScaffold(
      title: 'Profile',
      body: ListView(
        children: [
          const SectionHeader(title: 'Account'),
          AppCard(child: _AccountTile(userAsync: userAsync)),
          const SizedBox(height: 24),
          const SectionHeader(title: 'About'),
          AppCard(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Know About Me'),
                  subtitle: Text('Mutual device presence and reassurance'),
                ),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Environment'),
                  subtitle: Text(config.environment.name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the account row.
///
/// Checks `hasValue` before `hasError` deliberately: in Riverpod 3 an
/// `AsyncValue` can be loading and failed at once, and `when` would otherwise
/// show a spinner instead of the failure.
class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.userAsync});

  final AsyncValue<AppUser?> userAsync;

  @override
  Widget build(BuildContext context) {
    if (userAsync.hasValue) {
      final user = userAsync.requireValue;
      if (user == null) {
        return const ListTile(
          leading: Icon(Icons.person_off_outlined),
          title: Text('Not signed in'),
          subtitle: Text('Sign-in is implemented in a later phase.'),
        );
      }
      return ListTile(
        leading: const Icon(Icons.person),
        title: Text(user.displayName),
        subtitle: Text(user.id),
      );
    }

    if (userAsync.hasError) {
      return const ListTile(
        leading: Icon(Icons.error_outline),
        title: Text('Could not load your account'),
      );
    }

    return const ListTile(
      leading: Icon(Icons.person_outline),
      title: Text('Checking account…'),
    );
  }
}
