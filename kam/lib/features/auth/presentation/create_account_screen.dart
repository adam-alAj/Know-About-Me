import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_inline_message.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../domain/services/auth_service.dart';
import '../domain/validation/auth_input_validation.dart';
import 'providers/auth_providers.dart';

/// Create-account screen (SRS FR-001, Phase 4 Task 4, Task 5, Task 18).
///
/// Registration creates an account **and** a profile document. The screen reports
/// exactly what happened:
///
/// - rejected (validation, duplicate account, weak password, network) → nothing
///   was created, so the user may correct the form and retry;
/// - profile pending → the account exists but its profile does not, so the user
///   is told setup is incomplete and where to finish it (never reported as a
///   plain success);
/// - complete → the router guard moves the user into the authenticated area.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _submitting = false;
  AppMessageTone? _messageTone;
  String? _message;
  String? _messageTitle;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _busy => _submitting || ref.watch(authStateProvider).isBusy;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _message = null;
      _messageTitle = null;
      _messageTone = null;
    });

    final result = await ref
        .read(authStateProvider.notifier)
        .register(
          displayName: _displayNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      switch (result) {
        case RegistrationComplete():
          // The guard redirects into the app; nothing to report here.
          break;
        case RegistrationRejected(:final failure):
          _messageTitle = 'Could not create your account';
          _message = failure.message;
          _messageTone = AppMessageTone.error;
        case RegistrationProfilePending():
          // Stated plainly rather than hidden: the account exists, the profile
          // does not, and the user is told where to finish it.
          _messageTitle = 'Your account was created';
          _message =
              'We could not finish saving your profile. You can complete it '
              'from your profile screen.';
          _messageTone = AppMessageTone.warning;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(authAvailableProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Create account',
      body: ListView(
        children: [
          Text(
            'Your account is separate from any partner connection. Nothing is '
            'shared until you both explicitly agree.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),

          if (!available) ...[
            const AppInlineMessage(
              title: 'Accounts are unavailable',
              message:
                  'This build has no account service configured, so an account '
                  'cannot be created here.',
              tone: AppMessageTone.warning,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _displayNameController,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      helperText: 'Shown to the person you connect with',
                      border: OutlineInputBorder(),
                    ),
                    validator: AuthInputValidation.displayName,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: AuthInputValidation.email,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText:
                          'At least '
                          '${AuthInputValidation.minimumPasswordLength} '
                          'characters',
                      border: const OutlineInputBorder(),
                    ),
                    validator: AuthInputValidation.password,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _confirmPasswordController,
                    enabled: !_busy,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => AuthInputValidation.confirmPassword(
                      value,
                      password: _passwordController.text,
                    ),
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppInlineMessage(
                      message: _message!,
                      title: _messageTitle,
                      tone: _messageTone ?? AppMessageTone.info,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _busy
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : AppButton.primary(
                          label: 'Create account',
                          onPressed: available ? _submit : null,
                        ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Already registered?', style: theme.textTheme.bodyMedium),
              AppButton(
                variant: AppButtonVariant.text,
                label: 'Sign in',
                onPressed: _busy
                    ? null
                    : () => context.goNamed(AppRoutes.signIn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
