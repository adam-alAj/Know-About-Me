import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_inline_message.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../../core/ui/widgets/empty_view.dart';
import '../../../core/ui/widgets/error_view.dart';
import '../../../core/ui/widgets/loading_view.dart';
import '../../../core/ui/widgets/section_header.dart';
import '../domain/metric_definition.dart';
import '../domain/models/rule.dart';
import '../domain/rule_draft.dart';
import 'providers/rule_providers.dart';
import 'widgets/rule_choice_field.dart';
import 'widgets/rule_condition_editor.dart';
import 'widgets/rule_validation_message.dart';

/// Creates or edits one rule (SRS FR-026 – FR-040).
///
/// The screen owns a [RuleDraft] only; the canonical [Rule] is produced once, at
/// save time, after the domain validates the whole draft. A failed save keeps the
/// user on the builder with actionable feedback and never leaves a partial rule
/// behind (SRS FR-033, FR-037).
class RuleBuilderScreen extends ConsumerStatefulWidget {
  const RuleBuilderScreen({super.key, this.ruleId});

  /// The rule being edited, or `null` when creating a new one.
  final String? ruleId;

  @override
  ConsumerState<RuleBuilderScreen> createState() => _RuleBuilderScreenState();
}

class _RuleBuilderScreenState extends ConsumerState<RuleBuilderScreen> {
  final ScrollController _scrollController = ScrollController();

  RuleDraft? _draft;

  /// Whether the user has tried to save, which turns on validation feedback.
  bool _submitted = false;
  bool _saving = false;
  AppFailure? _saveFailure;

  bool get _isEditing => widget.ruleId != null;

  String get _title => _isEditing ? 'Edit rule' : 'New rule';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scopeAsync = ref.watch(ruleScopeProvider);

    if (scopeAsync.isLoading && !scopeAsync.hasValue) {
      return AppScaffold(
        title: _title,
        body: const LoadingView(label: 'Checking your connection'),
      );
    }

    final scope = scopeAsync.value;
    if (scope == null) {
      return AppScaffold(
        title: _title,
        body: const EmptyView(
          icon: Icons.link_off,
          title: 'No connection yet',
          message:
              'A rule describes the device you are connected with. Connect '
              'with someone first, then create a rule.',
        ),
      );
    }

    if (_isEditing && _draft == null) {
      final rulesAsync = ref.watch(rulesControllerProvider);
      if (!rulesAsync.hasValue) {
        return AppScaffold(
          title: _title,
          body: const LoadingView(label: 'Loading the rule'),
        );
      }
      final rule = _findRule(rulesAsync.requireValue, widget.ruleId!);
      if (rule == null) {
        return AppScaffold(
          title: _title,
          body: ErrorView(
            title: 'This rule is no longer available',
            message: 'It may have been deleted on another device.',
            retryLabel: 'Back to rules',
            onRetry: () => context.pop(),
          ),
        );
      }
      _draft = RuleDraft.fromRule(rule);
    }

    _draft ??= RuleDraft.newRule(
      ownerUserId: scope.ownerUserId,
      pairId: scope.pairId,
    );
    final draft = _draft!;

    // Recomputed every build so fixing a field clears its message immediately.
    final issues = draft.validate();
    final showIssues = _submitted;

    return AppScaffold(
      title: _title,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              if (_saveFailure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppInlineMessage(
                    tone: AppMessageTone.error,
                    title: 'The rule was not saved',
                    message: _saveFailure!.message,
                  ),
                ),
              if (showIssues) RuleValidationMessage(issues: issues),
              _nameField(draft, issues, showIssues),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(
                title: 'When this is true',
                subtitle: 'Conditions describe device state the app observes.',
              ),
              for (var index = 0; index < draft.conditions.length; index++) ...[
                RuleConditionEditor(
                  condition: draft.conditions[index],
                  index: index,
                  canRemove: draft.conditions.length > 1,
                  errorText: showIssues
                      ? _conditionError(issues, index)
                      : null,
                  onMetricChanged: (metric) => _changeMetric(index, metric),
                  onChanged: (condition) =>
                      _replaceCondition(index, condition),
                  onRemove: () => _removeCondition(index),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (draft.conditions.length > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                _groupOperatorField(draft),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppButton.secondary(
                label: 'Add condition',
                icon: Icons.add,
                onPressed: _addCondition,
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(
                title: 'Then interpret it as',
                subtitle: 'Your own wording for what a match might mean.',
              ),
              _interpretationFields(draft, issues, showIssues),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Options'),
              _enabledTile(draft),
              const SizedBox(height: AppSpacing.md),
              RuleChoiceField<int>(
                label: 'Repeating',
                value: draft.cooldownMinutes,
                helperText:
                    'How often this rule may act again while it keeps '
                    'matching.',
                options: const [
                  (0, 'Every time it matches'),
                  (5, 'At most every 5 minutes'),
                  (15, 'At most every 15 minutes'),
                  (30, 'At most every 30 minutes'),
                  (60, 'At most every hour'),
                  (120, 'At most every 2 hours'),
                  (240, 'At most every 4 hours'),
                ],
                onChanged: (minutes) => _update(
                  (draft) => draft.copyWith(cooldownMinutes: minutes),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const AppInlineMessage(
                tone: AppMessageTone.info,
                title: 'Facts and interpretations',
                message:
                    'Conditions describe device state the app can observe. '
                    'The interpretation is your own wording for what that '
                    'might mean — it is not a claim about what the other '
                    'person is doing.',
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_saving) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: AppSpacing.sm),
              ],
              _actions(draft),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------

  Widget _nameField(
    RuleDraft draft,
    List<RuleValidationIssue> issues,
    bool showIssues,
  ) {
    return TextFormField(
      key: const ValueKey('rule-name'),
      initialValue: draft.name,
      maxLength: RuleDraft.maxNameLength,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Rule name',
        hintText: 'For example: Long charging',
        border: const OutlineInputBorder(),
        errorText: showIssues
            ? _firstMessage(issues, const {'missing_name', 'name_too_long'})
            : null,
      ),
      onChanged: (value) => _update((draft) => draft.copyWith(name: value)),
    );
  }

  Widget _groupOperatorField(RuleDraft draft) {
    final all = draft.groupOperator == RuleGroupOperator.all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<RuleGroupOperator>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<RuleGroupOperator>(
              value: RuleGroupOperator.all,
              label: Text('All'),
            ),
            ButtonSegment<RuleGroupOperator>(
              value: RuleGroupOperator.any,
              label: Text('Any'),
            ),
          ],
          selected: {draft.groupOperator},
          onSelectionChanged: (selection) => _update(
            (draft) => draft.copyWith(groupOperator: selection.first),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          all
              ? 'The rule matches when every condition is true.'
              : 'The rule matches when at least one condition is true.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _interpretationFields(
    RuleDraft draft,
    List<RuleValidationIssue> issues,
    bool showIssues,
  ) {
    final isProbability = draft.outputKind == RuleOutputKind.probability;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RuleChoiceField<RuleOutputKind>(
          label: 'Interpretation type',
          value: draft.outputKind,
          options: [
            for (final kind in RuleOutputKind.values) (kind, kind.label),
          ],
          onChanged: (kind) => _update(
            (draft) => draft.copyWith(outputKind: kind),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const ValueKey('rule-output'),
          initialValue: draft.outputText,
          maxLength: RuleDraft.maxOutputLength,
          decoration: InputDecoration(
            labelText: isProbability
                ? 'What does it mean?'
                : draft.outputKind == RuleOutputKind.status
                ? 'Status text'
                : 'Message',
            hintText: isProbability
                ? 'For example: may be sleeping'
                : 'For example: away from home',
            border: const OutlineInputBorder(),
            errorText: showIssues
                ? _firstMessage(issues, const {
                    'missing_output',
                    'output_too_long',
                  })
                : null,
          ),
          onChanged: (value) =>
              _update((draft) => draft.copyWith(outputText: value)),
        ),
        if (isProbability) ...[
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('rule-probability'),
            initialValue: draft.probabilityText,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'User-defined probability (%)',
              border: const OutlineInputBorder(),
              helperText:
                  'Your own estimate, between 0 and 100. It is not a '
                  'calculated or verified probability.',
              errorText: showIssues
                  ? _firstMessage(issues, const {'invalid_probability'})
                  : null,
            ),
            onChanged: (value) => _update(
              (draft) => draft.copyWith(probabilityText: value),
            ),
          ),
        ],
      ],
    );
  }

  Widget _enabledTile(RuleDraft draft) {
    return Semantics(
      toggled: draft.enabled,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enabled'),
        subtitle: Text(
          draft.enabled
              ? 'This rule can be used when the app interprets device state.'
              : 'This rule is saved but will not be used.',
        ),
        value: draft.enabled,
        onChanged: (value) =>
            _update((draft) => draft.copyWith(enabled: value)),
      ),
    );
  }

  Widget _actions(RuleDraft draft) {
    return Row(
      children: [
        Expanded(
          child: AppButton.secondary(
            label: 'Cancel',
            onPressed: _saving ? null : () => context.pop(),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppButton.primary(
            label: _isEditing ? 'Save changes' : 'Save rule',
            icon: Icons.check,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Behaviour
  // ---------------------------------------------------------------------

  void _update(RuleDraft Function(RuleDraft draft) transform) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = transform(draft));
  }

  void _replaceCondition(int index, RuleDraftCondition condition) {
    _update(
      (draft) =>
          draft.copyWith(conditions: _withCondition(draft, index, condition)),
    );
  }

  void _changeMetric(int index, RuleMetric metric) {
    final definition = RuleMetrics.of(metric);
    final isState = definition.valueKind == RuleValueKind.state;
    _update((draft) {
      final current = draft.conditions[index];
      return draft.copyWith(
        conditions: _withCondition(
          draft,
          index,
          current.copyWith(
            metric: metric,
            operator: definition.allowedOperators.first,
            numericText: '',
            stateValue: isState ? definition.states.first.value : null,
            clearState: !isState,
          ),
        ),
      );
    });
  }

  List<RuleDraftCondition> _withCondition(
    RuleDraft draft,
    int index,
    RuleDraftCondition condition,
  ) {
    final next = [...draft.conditions];
    next[index] = condition;
    return next;
  }

  void _addCondition() {
    _update(
      (draft) => draft.copyWith(
        conditions: [
          ...draft.conditions,
          RuleDraftCondition(
            metric: RuleMetric.chargingDuration,
            operator: RuleOperator.greaterThanOrEqual,
          ),
        ],
      ),
    );
  }

  void _removeCondition(int index) {
    final draft = _draft;
    if (draft == null || draft.conditions.length <= 1) return;
    _update(
      (draft) =>
          draft.copyWith(conditions: [...draft.conditions]..removeAt(index)),
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;

    setState(() {
      _submitted = true;
      _saveFailure = null;
    });

    if (draft.validate().isNotEmpty) {
      // Bring the summary into view so the messages are actually seen.
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    setState(() => _saving = true);
    final result = await ref
        .read(rulesControllerProvider.notifier)
        .saveDraft(draft);
    if (!mounted) return;
    setState(() => _saving = false);

    result.fold(
      onSuccess: (rule) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('"${rule.name}" was saved.')));
        if (context.canPop()) context.pop();
      },
      onFailure: (failure) => setState(() => _saveFailure = failure),
    );
  }

  static Rule? _findRule(List<Rule> rules, String id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  static String? _firstMessage(
    List<RuleValidationIssue> issues,
    Set<String> codes,
  ) {
    for (final issue in issues) {
      if (codes.contains(issue.code)) return issue.message;
    }
    return null;
  }

  static String? _conditionError(List<RuleValidationIssue> issues, int index) {
    final prefix = 'Condition ${index + 1}:';
    for (final issue in issues) {
      if (issue.message.startsWith(prefix)) return issue.message;
    }
    return null;
  }
}
