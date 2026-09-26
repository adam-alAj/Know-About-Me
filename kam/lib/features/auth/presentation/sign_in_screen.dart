import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_inline_message.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../domain/validation/auth_input_validation.dart';
import 'providers/auth_providers.dart';

/// Sign-in screen (SRS FR-001, Phase 4 Task 6, Task 18).
///
/// The screen issues **no** Firebase call: it asks `authStateProvider.notifier`,
/// which asks `AuthService`, which asks the repository interface (constraint 4).
///
/// Form state (field contents, submit-in-flight, the last message) is ephemeral
/// UI state and therefore lives here rather than in a provider (ADR-006).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  String? _failureMessage;

  @override
  void dispose() {
    _emailController.dispose();
    // The password is dropped as soon as the screen goes away; it is never
    // stored, logged or sent anywhere but the provider (constraint 6, 7).
    _passwordController.dispose();
    super.dispose();
  }

  bool get _busy => _submitting || ref.watch(authStateProvider).isBusy;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Keyboard dismissal keeps the error message visible on small screens.
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _failureMessage = null;
    });

    final result = await ref
        .read(authStateProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      // Already a user-safe message from the classified failure.
      _failureMessage = result.failureOrNull?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(authAvailableProvider);
    final unavailableReason = ref.watch(authUnavailableReasonProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Sign in',
      body: ListView(
        children: [
          Text(
            'Sign in to connect your device with someone you trust.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Honest capability reporting: an unconfigured build says so instead
          // of failing at submit time (SRS constraint 10).
          if (!available) ...[
            AppInlineMessage(
              title: 'Accounts are unavailable',
              message:
                  unavailableReason ??
                  'This build has no account service configured.',
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
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: AuthInputValidation.password,
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_failureMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppInlineMessage(
                      message: _failureMessage!,
                      tone: AppMessageTone.error,
                      title: 'Could not sign you in',
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _busy
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : AppButton.primary(
                          label: 'Sign in',
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
              Text('No account yet?', style: theme.textTheme.bodyMedium),
              AppButton(
                variant: AppButtonVariant.text,
                label: 'Create one',
                onPressed: _busy
                    ? null
                    : () => context.goNamed(AppRoutes.createAccount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
