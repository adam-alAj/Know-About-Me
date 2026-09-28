import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/empty_view.dart';
import '../../../core/ui/widgets/error_view.dart';
import '../../../core/ui/widgets/loading_view.dart';
import '../../../core/ui/widgets/section_header.dart';
import '../../pairing/presentation/providers/pairing_providers.dart';
import '../domain/models/rule.dart';
import 'providers/rule_providers.dart';
import 'widgets/rule_card.dart';

/// Rule management: list, create, enable/disable and delete (SRS FR-033,
/// FR-034, FR-038).
///
/// The screen observes the rule list and the active connection, and never talks
/// to Firestore: every read and write goes through [RulesController].
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(ruleScopeProvider).value;

    return AppScaffold(
      title: 'Rules',
      floatingActionButton: scope == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.ruleCreatePath),
              icon: const Icon(Icons.add),
              label: const Text('Create rule'),
            ),
      body: const _RulesBody(),
    );
  }
}

class _RulesBody extends ConsumerWidget {
  const _RulesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeAsync = ref.watch(ruleScopeProvider);

    if (scopeAsync.isLoading && !scopeAsync.hasValue) {
      return const LoadingView(label: 'Checking your connection');
    }
    if (scopeAsync.hasError) {
      final failure = AppFailure.fromException(
        scopeAsync.error!,
        scopeAsync.stackTrace,
      );
      return ErrorView(
        title: 'Your connection could not be checked',
        message: failure.message,
        onRetry: () => ref.invalidate(pairMembershipsProvider),
      );
    }
    if (scopeAsync.value == null) {
      return const EmptyView(
        icon: Icons.link_off,
        title: 'No connection yet',
        message:
            'Rules describe what you would like the app to notice about the '
            'device you are connected with. Connect with someone first, then '
            'come back to create your first rule.',
      );
    }

    final rulesAsync = ref.watch(rulesControllerProvider);
    if (!rulesAsync.hasValue) {
      if (rulesAsync.hasError) {
        final failure = AppFailure.fromException(
          rulesAsync.error!,
          rulesAsync.stackTrace,
        );
        return ErrorView(
          title: 'Your rules could not be loaded',
          message: failure.message,
          onRetry: () =>
              ref.read(rulesControllerProvider.notifier).retry(),
        );
      }
      return const LoadingView(label: 'Loading your rules');
    }

    final rules = rulesAsync.requireValue;
    if (rules.isEmpty) return const _EmptyRules();

    return _RulesList(rules: rules);
  }
}

/// Shown when the user has an active connection but no rules yet (SRS FR-033).
class _EmptyRules extends StatelessWidget {
  const _EmptyRules();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EmptyView(
            icon: Icons.rule_outlined,
            title: 'No rules yet',
            message:
                'Create a rule to describe what device states you would like '
                'the app to notice, and how you would like to interpret them.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppButton.primary(
            label: 'Create rule',
            icon: Icons.add,
            onPressed: () => context.push(AppRoutes.ruleCreatePath),
          ),
        ),
      ],
    );
  }
}

class _RulesList extends ConsumerStatefulWidget {
  const _RulesList({required this.rules});

  final List<Rule> rules;

  @override
  ConsumerState<_RulesList> createState() => _RulesListState();
}

class _RulesListState extends ConsumerState<_RulesList> {
  /// Rule ids with a write in flight, so their controls are disabled and a
  /// second tap cannot double-submit.
  final Set<String> _pending = <String>{};

  Future<void> _toggleEnabled(Rule rule) async {
    setState(() => _pending.add(rule.id));
    final result = await ref
        .read(rulesControllerProvider.notifier)
        .setEnabled(rule, enabled: !rule.enabled);
    if (!mounted) return;
    setState(() => _pending.remove(rule.id));
    result.fold(onSuccess: (_) {}, onFailure: (failure) => _show(failure));
  }

  Future<void> _confirmDelete(Rule rule) async {
    // Deleting is destructive, so it is confirmed and the prompt names the rule
    // the way the user knows it — never by id (SRS FR-038, FR-045).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this rule?'),
        content: Text(
          'Delete "${rule.name}"? This cannot be undone. '
          'Interpretations it already produced are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _pending.add(rule.id));
    final result = await ref
        .read(rulesControllerProvider.notifier)
        .removeRule(rule);
    if (!mounted) return;
    setState(() => _pending.remove(rule.id));
    result.fold(
      onSuccess: (_) =>
          _showMessage('"${rule.name}" was deleted.', isError: false),
      onFailure: _show,
    );
  }

  void _show(AppFailure failure) => _showMessage(failure.message, isError: true);

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: widget.rules.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const SectionHeader(
            title: 'Your rules',
            subtitle:
                'Interpretations you defined. They describe a possibility, '
                'not a fact about the other person.',
          );
        }
        final rule = widget.rules[index - 1];
        return RuleCard(
          rule: rule,
          busy: _pending.contains(rule.id),
          onEdit: () => context.push(AppRoutes.ruleEditPath(rule.id)),
          onToggleEnabled: () => _toggleEnabled(rule),
          onDelete: () => _confirmDelete(rule),
        );
      },
    );
  }
}
