import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/time/date_time_utils.dart';
import '../../../../core/ui/widgets/app_card.dart';
import '../../../../core/ui/widgets/app_inline_message.dart';
import '../../../../core/ui/widgets/freshness_indicator.dart';
import '../../domain/models/interpretation_result.dart';
import '../../domain/rule_description.dart';
import '../../domain/rule_draft.dart';
import 'interpretation_type_badge.dart';

/// One rule's interpretation of the partner's current state (SRS FR-030,
/// FR-031, FR-045).
///
/// The card keeps three things visibly apart, because collapsing them is the one
/// mistake this phase exists to prevent (STEP 5, STEP 30):
///
/// 1. **what was observed** — [ObservedFactsSection] lists the facts the engine
///    used, in the engine's own wording;
/// 2. **what the user's rule says** — the rule name and its condition, read back
///    verbatim from Phase 14's description helpers;
/// 3. **what the user's rule means** — the user's own wording, introduced by
///    "Based on your rule" and, when a percentage is configured, labelled
///    "User-defined probability".
///
/// Nothing here produces language of its own. There is no sentence anywhere that
/// turns an observation into a claim about a person, so the app can never state
/// "they are asleep" — only "your rule, which you call *Possible sleep period,
/// 70%*, matched on these two facts."
class RuleInterpretationCard extends StatelessWidget {
  const RuleInterpretationCard({
    super.key,
    required this.result,
    this.now,
  });

  final InterpretationResult result;

  /// Current time, used only to render how old the evidence is. When null the
  /// age is omitted and only the freshness classification is shown.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matched = result.isMatched;
    final explanation = result.explanation;

    return AppCard(
      semanticLabel: _semanticLabel(result),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.ruleName,
            style: theme.textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // The type sits on its own line rather than beside the name: a long
          // rule name, a long type label and a large text scale would otherwise
          // compete for the same width and overflow the card.
          const SizedBox(height: AppSpacing.xs),
          InterpretationTypeBadge(type: result.type),
          const SizedBox(height: AppSpacing.md),
          if (matched)
            _InterpretationBody(result: result)
          else
            AppInlineMessage(
              title: 'Not enough information',
              message:
                  explanation ??
                  'This rule could not be checked against the current state.',
              tone: AppMessageTone.info,
            ),
          const SizedBox(height: AppSpacing.md),
          ObservedFactsSection(result: result),
          const SizedBox(height: AppSpacing.md),
          _EvidenceFooter(result: result, now: now),
        ],
      ),
    );
  }

  /// One sentence that states the relationship without adding a conclusion.
  static String _semanticLabel(InterpretationResult result) {
    if (!result.isMatched) {
      return '${result.ruleName}: not enough information to interpret.';
    }
    final title = result.title ?? result.type.label;
    final probability = result.userDefinedProbability;
    final suffix = probability == null
        ? ''
        : ' User-defined probability $probability percent, set by you.';
    return 'Based on your rule ${result.ruleName}: $title.$suffix';
  }
}

/// The user's own interpretation, introduced as such.
class _InterpretationBody extends StatelessWidget {
  const _InterpretationBody({required this.result});

  final InterpretationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = result.title ?? result.type.label;
    final probability = result.userDefinedProbability;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Based on your rule',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(title, style: theme.textTheme.titleMedium),
        if (probability != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InterpretationProbability(
            subject: result.type == RuleOutputKind.probability ? title : null,
            percent: probability,
          ),
        ],
      ],
    );
  }
}

/// The user's configured percentage, always labelled as user-defined.
///
/// The wording never implies a measurement (STEP 20). "User-defined
/// probability" is used rather than "probability that X", because the app has no
/// model that could produce the latter (SRS FR-030, NFR-023, NFR-041).
class InterpretationProbability extends StatelessWidget {
  const InterpretationProbability({
    super.key,
    required this.percent,
    this.subject,
  });

  /// The user's configured percentage, 0–100.
  final int percent;

  /// The wording the user gave it, when the rule already names it.
  final String? subject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'User-defined probability: $percent%';

    return Semantics(
      label: subject == null
          ? '$label. This value was set by you, not measured.'
          : '$label, for $subject. This value was set by you, not measured.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.percent,
              size: 16,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The observations the interpretation is based on, plus the rule that used
/// them (STEP 6, STEP 19).
///
/// Facts are shown in the engine's own words so the wording cannot drift between
/// what was evaluated and what the user reads. The condition is rendered from
/// the persisted rule with Phase 14's helpers, so it always matches the rule as
/// saved — never a re-typed copy.
class ObservedFactsSection extends StatelessWidget {
  const ObservedFactsSection({super.key, required this.result});

  final InterpretationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.isMatched ? 'Why this rule matched' : 'Your rule',
          style: caption,
        ),
        if (result.facts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          for (final fact in result.facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: theme.textTheme.bodyMedium),
                  Expanded(
                    child: Text(
                      fact.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Rule condition: ${RuleDescription.conditions(result.rule)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// How current the interpretation is, and when it was last checked.
class _EvidenceFooter extends StatelessWidget {
  const _EvidenceFooter({required this.result, this.now});

  final InterpretationResult result;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final observed = result.observationTime;
    final current = now;
    final age = observed == null || current == null
        ? null
        : current.toUtc().difference(observed.toUtc());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FreshnessIndicator(freshness: result.freshness, age: age),
        if (result.isBasedOnStaleData) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This interpretation is based on information that is no longer current.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Last checked ${DateTimeUtils.formatLocalTimestamp(result.evaluatedAt)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
