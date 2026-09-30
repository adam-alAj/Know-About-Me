import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/ui/widgets/app_inline_message.dart';
import '../../../../core/ui/widgets/loading_view.dart';
import '../../../../core/ui/widgets/section_header.dart';
import '../providers/rule_evaluation_providers.dart';
import 'rule_interpretation_card.dart';

/// The dashboard's "what your rules say" section (STEP 17).
///
/// Every state has an explicit, calm rendering, and none of them is invented:
///
/// * loading — the rules or the partner state are still arriving;
/// * no authorized partner state — there is nothing to interpret, and saying so
///   is more honest than an empty list (STEP 25);
/// * a failure to read the rules — reported plainly, with no interpretations
///   presented as if they existed (STEP 29);
/// * nothing to show — every enabled rule was evaluated and none of them applies
///   right now (STEP 3);
/// * results — one card per rule, each keeping facts, rule and interpretation
///   apart.
///
/// A rule that was evaluated and is simply false is not listed: it would add
/// noise without adding information (STEP 10).
class RuleInterpretationsSection extends ConsumerWidget {
  const RuleInterpretationsSection({super.key, this.now});

  /// Current time, so evidence ages can be rendered. Supplied by the host
  /// screen's own clock tick; when null, only the freshness classification is
  /// shown.
  final DateTime? now;

  static const String loadingLabel = 'Checking your rules';
  static const String waitingTitle = 'Nothing to interpret yet';
  static const String waitingMessage =
      'Once your partner shares device state, your rules can be checked against it.';
  static const String emptyTitle = 'No rule applies right now';
  static const String emptyMessage =
      'Your enabled rules were checked against your partner’s shared state, and none of them matched.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Display only. Notification delivery is owned by the root
    // `notificationDeliveryProvider`, so an alert is raised from any screen,
    // not only while this section is mounted.
    final state = ref.watch(ruleEvaluationProvider);
    final current = now ?? ref.watch(clockProvider).nowUtc();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'What your rules say',
          subtitle: 'Your own interpretations of the shared device state',
        ),
        if (state.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: LoadingView(label: loadingLabel),
          )
        else if (state.hasError)
          AppInlineMessage(
            title: 'Your rules could not be checked',
            message:
                state.errorMessage ??
                'Your rules could not be checked right now.',
            tone: AppMessageTone.warning,
          )
        else if (!state.hasPartnerState)
          const AppInlineMessage(
            title: waitingTitle,
            message: waitingMessage,
          )
        else if (state.results.isEmpty)
          const AppInlineMessage(title: emptyTitle, message: emptyMessage)
        else
          for (final result in state.results)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RuleInterpretationCard(result: result, now: current),
            ),
      ],
    );
  }

}
