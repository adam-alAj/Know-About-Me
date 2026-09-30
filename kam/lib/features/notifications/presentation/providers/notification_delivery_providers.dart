import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../../../auth/domain/models/user_preferences.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../history/domain/models/device_event.dart';
import '../../../history/presentation/history_providers.dart';
import '../../../pairing/presentation/providers/pairing_providers.dart';
import '../../../rules/domain/models/interpretation_result.dart';
import '../../../rules/presentation/providers/rule_evaluation_providers.dart';
import '../../domain/rule_notification_planner.dart';

/// Delivers eligible rule notifications from the application root.
///
/// Notification delivery used to run inside the dashboard's rule section, which
/// meant an alert only reached the user while that exact screen happened to be
/// mounted. Delivery is a consequence of a rule evaluation, not of a widget
/// being visible, so the trigger now lives with the other root listeners
/// (`historyEventListenersProvider`) and is mounted once, in `KamApp`.
///
/// It performs no I/O of its own beyond asking the local-notification service to
/// present an alert, and it never reaches the network.
final notificationDeliveryProvider = Provider<NotificationDelivery>((ref) {
  final delivery = NotificationDelivery(ref);
  ref.listen(ruleEvaluationProvider, (previous, next) {
    if (next.hasPartnerState && !next.isLoading && !next.hasError) {
      unawaited(delivery.deliver(next));
    }
  });
  // A new signed-in user starts with no alert bookkeeping, so one account's
  // cooldown/dedupe state can never suppress or leak into another's alerts.
  ref.listen(currentIdentityProvider, (previous, next) {
    if (previous?.uid != next?.uid) delivery.reset();
  });
  ref.onDispose(delivery.dispose);
  return delivery;
});

/// Owns the "raise this alert once" bookkeeping for one app session.
class NotificationDelivery {
  NotificationDelivery(this._ref);

  final Ref _ref;

  /// Alert keys already attempted this session, so a re-delivered snapshot is
  /// not a second alert.
  final Set<String> _attemptedAlertKeys = <String>{};

  /// When each rule last raised an alert, for the rule's own cooldown.
  final Map<String, DateTime> _lastAlertAt = <String, DateTime>{};

  /// Forgets all bookkeeping. Called on sign-out and on disposal.
  void reset() {
    _attemptedAlertKeys.clear();
    _lastAlertAt.clear();
  }

  void dispose() => reset();

  /// Raises one notification per newly matched, fresh, eligible rule.
  Future<void> deliver(RuleEvaluationState state) async {
    final preferences = _ref
        .read(currentUserPreferencesProvider)
        .value
        ?.valueOrNull;
    if (preferences == null ||
        preferences.notificationPreference ==
            NotificationPreference.noNotifications) {
      return;
    }

    final service = _ref.read(localNotificationServiceProvider);
    final permission = await service.permissionState();
    if (permission.valueOrNull != NotificationPermissionState.granted) {
      for (final item in state.results.where((item) => item.isNewMatch)) {
        await _recordAlert(item, shown: false, reason: 'permissionUnavailable');
      }
      return;
    }

    const planner = RuleNotificationPlanner();
    for (final item in state.results) {
      if (!item.rule.enabled ||
          !item.isNewMatch ||
          item.isBasedOnStaleData ||
          item.observationTime == null) {
        continue;
      }
      final key =
          '${item.ruleId}:v${item.ruleVersion}:'
          '${item.evaluation.evaluationId ?? item.evaluatedAt.toIso8601String()}';
      final lastAlert = _lastAlertAt[item.ruleId] ?? item.rule.lastTriggeredAt;
      if (lastAlert != null &&
          item.evaluatedAt.toUtc().difference(lastAlert.toUtc()) <
              item.rule.cooldown) {
        await _recordAlert(item, shown: false, reason: 'cooldown');
        continue;
      }
      if (!_attemptedAlertKeys.add(key)) continue;
      final plan = planner.plan(
        rule: item.rule,
        result: item.evaluation,
        preference: preferences.notificationPreference,
      );
      if (!plan.shouldNotify) {
        await _recordAlert(item, shown: false, reason: 'notEligible');
        continue;
      }
      // The lock-screen text stays generic: user-authored rules and partner
      // details are shown only after the user opens the authorized app.
      final delivery = await service.show(
        LocalNotificationRequest(
          id: key,
          title: 'Rule alert',
          body: 'A rule you created matches shared device state. '
              'Open the app to review it.',
          payload: item.ruleId,
        ),
      );
      await _recordAlert(
        item,
        shown: delivery.isSuccess,
        reason: delivery.isSuccess ? 'shown' : 'deliveryFailed',
      );
      if (delivery.isSuccess) {
        _lastAlertAt[item.ruleId] = item.evaluatedAt.toUtc();
      }
    }
  }

  Future<void> _recordAlert(
    InterpretationResult item, {
    required bool shown,
    required String reason,
  }) async {
    final scope = _ref.read(partnerScopeProvider).value;
    final uid = _ref.read(currentIdentityProvider)?.uid;
    if (scope == null || uid == null) return;
    final key =
        '${scope.pairId}|$uid|${item.ruleId}|v${item.ruleVersion}|'
        '$reason|${item.evaluatedAt.toUtc().toIso8601String()}';
    await _ref.read(historyRecorderProvider).record(
      DeviceEvent(
        id: historyEventId(key),
        pairId: scope.pairId,
        ownerUserId: uid,
        type: shown
            ? DeviceEventType.ruleNotificationGenerated
            : DeviceEventType.notificationSuppressed,
        occurredAt: item.evaluatedAt.toUtc(),
        observedAt: item.observationTime,
        source: 'notification',
        deduplicationKey: historyEventId(key),
        summary: shown
            ? 'A rule notification was shown'
            : 'A rule notification was suppressed',
        payload: <String, Object?>{
          'outcome': reason,
          'ruleVersion': item.ruleVersion,
        },
      ),
    );
  }
}
