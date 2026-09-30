import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/firebase/firebase_error_mapper.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/ui/data_state_view.dart';
import '../../../core/ui/presentation_mapping.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_inline_message.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/loading_view.dart';
import '../../../core/ui/widgets/section_header.dart';
import '../domain/models/app_user.dart';
import '../domain/models/user_preferences.dart';
import '../domain/validation/auth_input_validation.dart';
import 'providers/auth_providers.dart';
import 'providers/profile_controller.dart';

/// Profile and account screen (SRS FR-002, FR-042; Phase 4 Task 14, Task 15, 18).
///
/// Three distinct reads are represented separately, because conflating them would
/// hide the truth:
///
/// - **identity** — always present while signed in;
/// - **profile document** — may be missing, which is shown as an explicit
///   "finish setting up" state rather than a fabricated user;
/// - **private preferences** — may be defaults because nothing is stored yet.
///
/// The screen never calls Firebase or Firestore; it reads providers and asks
/// `profileControllerProvider` to write (constraint 4).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final presentation = PresentationMapping.fromAsyncNullableResult(
      profileAsync,
    );

    return AppScaffold(
      title: 'Profile',
      body: ListView(
        children: [
          const SectionHeader(title: 'Account'),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: Text(identity?.email ?? 'No email available'),
                  subtitle: const Text('Sign-in email'),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    identity == null
                        ? 'Not signed in'
                        : 'Your account is connected to this device only',
                  ),
                  subtitle: identity == null
                      ? const Text('Sign in to manage your profile.')
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          const SectionHeader(title: 'Your profile'),
          AppCard(
            child: DataStateView(
              presentation: presentation,
              loadingLabel: 'Loading your profile',
              onRetry: identity == null
                  ? null
                  : () => ref.invalidate(userProfileProvider(identity.uid)),
              // No profile document: offer to create it rather than pretending
              // one exists (Phase 4 Task 14).
              emptyBuilder: (context) =>
                  _ProfileSetup(identityPresent: identity != null),
              loadedBuilder: (context) => _ProfileEditor(
                profile: profileAsync.requireValue.valueOrNull,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          const SectionHeader(
            title: 'Notifications',
            subtitle: 'How rule interpretations may reach you (FR-042)',
          ),
          AppCard(child: _NotificationPreferenceSection(uid: identity?.uid)),
          const SizedBox(height: AppSpacing.lg),

          const SectionHeader(title: 'Session'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Signing out clears this device. Your account and profile are '
                  'kept, and you can sign in again at any time.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton.secondary(
                  label: 'Sign out',
                  icon: Icons.logout,
                  onPressed: identity == null
                      ? null
                      : () => ref.read(authStateProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          const SectionHeader(title: 'About'),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Know About Me'),
              subtitle: Text(
                'Mutual device presence and reassurance · '
                '${ref.watch(appConfigProvider).environment.name}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the authenticated user has no profile document yet.
class _ProfileSetup extends StatelessWidget {
  const _ProfileSetup({required this.identityPresent});

  final bool identityPresent;

  @override
  Widget build(BuildContext context) {
    if (!identityPresent) {
      return const ListTile(
        leading: Icon(Icons.person_off_outlined),
        title: Text('Not signed in'),
        subtitle: Text('Sign in to set up your profile.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppInlineMessage(
          title: 'Your profile is not set up yet',
          message:
              'Your account exists, but no profile was saved for it. Choose a '
              'display name to finish setting it up.',
          tone: AppMessageTone.warning,
        ),
        const SizedBox(height: AppSpacing.md),
        _DisplayNameForm(
          initialName: null,
          submitLabel: 'Finish setup',
          fieldLabel: 'Display name',
        ),
      ],
    );
  }
}

/// Shows and edits an existing profile.
///
/// The current name appears once — in the field itself — rather than repeated as
/// a separate label, so the screen never shows two versions of the same value.
class _ProfileEditor extends StatelessWidget {
  const _ProfileEditor({required this.profile});

  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    final user = profile;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          leading: Icon(Icons.badge_outlined),
          title: Text('Display name'),
          subtitle: Text(
            'Shown to the person you connect with once you both agree',
          ),
        ),
        _DisplayNameForm(
          initialName: user.displayName,
          submitLabel: 'Save name',
          fieldLabel: 'Display name',
        ),
      ],
    );
  }
}

/// Display-name form, shared by the "finish setup" and "edit" paths.
///
/// Writes through `ProfileController`, so validation, the in-flight state and the
/// create-or-update decision are all handled once (SRS Task 15).
class _DisplayNameForm extends ConsumerStatefulWidget {
  const _DisplayNameForm({
    required this.initialName,
    required this.submitLabel,
    required this.fieldLabel,
  });

  final String? initialName;
  final String submitLabel;
  final String fieldLabel;

  @override
  ConsumerState<_DisplayNameForm> createState() => _DisplayNameFormState();
}

class _DisplayNameFormState extends ConsumerState<_DisplayNameForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    // The outcome needs no snack bar: the controller state is rendered inline
    // below the field, which keeps the message on screen while the user fixes
    // the input instead of showing the same failure twice.
    await ref
        .read(profileControllerProvider.notifier)
        .saveDisplayName(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(profileControllerProvider);
    final saving = mutation is ProfileSaving;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _controller,
            enabled: !saving,
            textInputAction: TextInputAction.done,
            maxLength: AuthInputValidation.maximumDisplayNameLength,
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              border: const OutlineInputBorder(),
            ),
            validator: AuthInputValidation.displayName,
            onFieldSubmitted: (_) => saving ? null : _save(),
          ),
          if (mutation case ProfileSaveFailed(:final failure)) ...[
            AppInlineMessage(
              message: failure.message,
              tone: AppMessageTone.error,
              title: 'Could not save your profile',
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (saving)
            const Center(child: CircularProgressIndicator.adaptive())
          else
            AppButton.primary(label: widget.submitLabel, onPressed: _save),
        ],
      ),
    );
  }
}

/// Notification preference selector (SRS FR-042).
class _NotificationPreferenceSection extends ConsumerWidget {
  const _NotificationPreferenceSection({required this.uid});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid == null) {
      return const ListTile(
        leading: Icon(Icons.notifications_off_outlined),
        title: Text('Not signed in'),
        subtitle: Text('Sign in to choose notification preferences.'),
      );
    }

    final preferencesAsync = ref.watch(userPreferencesProvider(uid!));

    if (preferencesAsync.isLoading) {
      return const SizedBox(
        height: 96,
        child: LoadingView(label: 'Loading preferences'),
      );
    }

    // A thrown stream error and a classified failure both become a safe message.
    final AppFailure? failure = preferencesAsync.hasError
        ? FirebaseErrorMapper.toFailure(
            preferencesAsync.error!,
            preferencesAsync.stackTrace,
          )
        : preferencesAsync.value?.failureOrNull;
    if (failure != null) {
      return AppInlineMessage(
        message: failure.message,
        tone: AppMessageTone.error,
        title: 'Preferences unavailable',
      );
    }

    final preferences =
        preferencesAsync.value?.valueOrNull ?? UserPreferences.defaults;
    final saving = ref.watch(profileControllerProvider) is ProfileSaving;

    // A dropdown rather than radio tiles: no deprecated selection APIs, and it
    // stays a single accessible control at large text scales (NFR-028).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<NotificationPreference>(
          initialValue: preferences.notificationPreference,
          decoration: const InputDecoration(
            labelText: 'Notification preference',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final preference in NotificationPreference.values)
              DropdownMenuItem<NotificationPreference>(
                value: preference,
                child: Text(_labelFor(preference)),
              ),
          ],
          onChanged: saving
              ? null
              : (selected) {
                  if (selected == null) return;
                  ref.read(profileControllerProvider.notifier)
                      .setNotificationPreference(selected);
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Notifications are checked only while the app is active. Permission is requested only when you choose below.',
            style: Theme.of(context).textTheme.bodySmall),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Enable device notifications'),
            onPressed: () async {
              final outcome = await ref.read(localNotificationServiceProvider).requestPermission();
              if (!context.mounted) return;
              final state = outcome.valueOrNull;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(state == NotificationPermissionState.granted
                    ? 'Device notifications are enabled.'
                    : 'Notifications are unavailable or denied. You can enable them in your device settings.'),
              ));
            },
          ),
        ),
      ],
    );
  }

  static String _labelFor(NotificationPreference preference) {
    switch (preference) {
      case NotificationPreference.allRuleNotifications:
        return 'All rule notifications';
      case NotificationPreference.importantOnly:
        return 'Important only';
      case NotificationPreference.specificRulesOnly:
        return 'Only rules I mark';
      case NotificationPreference.noNotifications:
        return 'No notifications';
    }
  }
}
