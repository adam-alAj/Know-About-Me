import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/ui/widgets/app_inline_message.dart';
import '../../../../core/ui/widgets/loading_view.dart';
import '../../../../core/ui/widgets/section_header.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/domain/models/user_preferences.dart';
import '../../../notifications/domain/rule_notification_planner.dart';
import '../../../history/domain/models/device_event.dart';
import '../../../history/presentation/history_providers.dart';
import '../../../pairing/presentation/providers/pairing_providers.dart';
import '../../domain/models/interpretation_result.dart';
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
    final state = ref.watch(ruleEvaluationProvider);
    ref.listen(ruleEvaluationProvider, (previous, next) {
      if (next.hasPartnerState && !next.isLoading && !next.hasError) {
        unawaited(_deliverNewMatches(ref, next));
      }
    });
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

  Future<void> _deliverNewMatches(WidgetRef ref, RuleEvaluationState state) async {
    final preferences = ref.read(currentUserPreferencesProvider).value?.valueOrNull;
    if (preferences == null ||
        preferences.notificationPreference == NotificationPreference.noNotifications) {
      return;
    }
    final service = ref.read(localNotificationServiceProvider);
    final permission = await service.permissionState();
    if (permission.valueOrNull != NotificationPermissionState.granted) {
      for (final item in state.results.where((item) => item.isNewMatch)) {
        await _recordAlert(ref, item, shown: false, reason: 'permissionUnavailable');
      }
      return;
    }
    const planner = RuleNotificationPlanner();
    for (final item in state.results) {
      if (!item.rule.enabled || !item.isNewMatch || item.isBasedOnStaleData ||
          item.observationTime == null) {
        continue;
      }
      final key = '${item.ruleId}:v${item.ruleVersion}:${item.evaluation.evaluationId ?? item.evaluatedAt.toIso8601String()}';
      final lastAlert = _lastAlertAt[item.ruleId] ?? item.rule.lastTriggeredAt;
      if (lastAlert != null &&
          item.evaluatedAt.toUtc().difference(lastAlert.toUtc()) < item.rule.cooldown) {
        await _recordAlert(ref, item, shown: false, reason: 'cooldown');
        continue;
      }
      if (!_attemptedAlertKeys.add(key)) continue;
      final plan = planner.plan(
        rule: item.rule,
        result: item.evaluation,
        preference: preferences.notificationPreference,
      );
      if (!plan.shouldNotify) {
        await _recordAlert(ref, item, shown: false, reason: 'notEligible');
        continue;
      }
      // Lock screen text stays generic: user-authored rules and partner details
      // are shown only after the user opens the authorized app.
      final delivery = await service.show(LocalNotificationRequest(
        id: key,
        title: 'Rule alert',
        body: 'A rule you created matches shared device state. Open the app to review it.',
        payload: item.ruleId,
      ));
      await _recordAlert(ref, item, shown: delivery.isSuccess,
          reason: delivery.isSuccess ? 'shown' : 'deliveryFailed');
      if (delivery.isSuccess) _lastAlertAt[item.ruleId] = item.evaluatedAt.toUtc();
    }
  }

  Future<void> _recordAlert(WidgetRef ref, InterpretationResult item, {
    required bool shown, required String reason,
  }) async {
    final scope = ref.read(partnerScopeProvider).value;
    final uid = ref.read(currentIdentityProvider)?.uid;
    if (scope == null || uid == null) return;
    final key = '${scope.pairId}|$uid|${item.ruleId}|v${item.ruleVersion}|$reason|${item.evaluatedAt.toUtc().toIso8601String()}';
    await ref.read(historyRecorderProvider).record(DeviceEvent(
      id: historyEventId(key), pairId: scope.pairId, ownerUserId: uid,
      type: shown ? DeviceEventType.ruleNotificationGenerated : DeviceEventType.notificationSuppressed,
      occurredAt: item.evaluatedAt.toUtc(), observedAt: item.observationTime,
      source: 'notification', deduplicationKey: historyEventId(key),
      summary: shown ? 'A rule notification was shown' : 'A rule notification was suppressed',
      payload: <String, Object?>{'outcome': reason, 'ruleVersion': item.ruleVersion},
    ));
  }
}

final Set<String> _attemptedAlertKeys = <String>{};
final Map<String, DateTime> _lastAlertAt = <String, DateTime>{};
