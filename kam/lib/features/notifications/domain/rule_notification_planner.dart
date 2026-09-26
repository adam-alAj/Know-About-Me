import '../../auth/domain/models/user_preferences.dart';
import '../../rules/domain/models/rule.dart';
import '../../rules/domain/rule_evaluation.dart';

/// The outcome of deciding whether a rule match should notify the user.
enum NotificationDecision {
  /// Raise a local notification now.
  notify,

  /// The user's notification preference excludes this rule (FR-042).
  suppressedByPreference,

  /// The condition is genuinely false.
  notMatched,

  /// The condition could not be evaluated because device state was missing or
  /// stale. Never presented as a match (FR-048, NFR-025).
  indeterminate,

  /// The rule matched again inside its cooldown window (FR-039).
  suppressedByCooldown,

  /// This exact interpretation has already been notified.
  duplicate,
}

/// The decision plus enough context to explain it.
///
/// A decision always carries a [reason], so the application never silently drops
/// a notification without a traceable explanation (constraint: do not hide
/// problems).
class RuleNotificationPlan {
  const RuleNotificationPlan({
    required this.decision,
    required this.reason,
    this.ruleId,
    this.title,
    this.body,
    this.dedupeKey,
  });

  final NotificationDecision decision;
  final String reason;

  /// Present when [decision] is [NotificationDecision.notify].
  final String? ruleId;
  final String? title;
  final String? body;

  /// Stable key identifying this specific notification, used to avoid raising
  /// the same alert twice.
  final String? dedupeKey;

  bool get shouldNotify => decision == NotificationDecision.notify;

  @override
  String toString() =>
      'RuleNotificationPlan(${decision.name}${ruleId != null ? ', $ruleId' : ''}: $reason)';
}

/// Decides whether a completed rule evaluation should raise a **local**
/// notification on this device.
///
/// This is the Spark-compatible replacement for a notification-dispatch Cloud
/// Function. It is safe on the client because the trigger is data the user is
/// already authorized to read and the sink is the user's own device — no
/// cross-device send happens, so no server credential is needed.
class RuleNotificationPlanner {
  const RuleNotificationPlanner({this.notifiableRuleIds = const <String>{}});

  /// Rule ids the user has explicitly marked as notifiable.
  ///
  /// Used for [NotificationPreference.specificRulesOnly] and
  /// [NotificationPreference.importantOnly]. "Important" is not yet a
  /// first-class field on [Rule], so the caller supplies the marked set; when it
  /// is empty those preferences correctly notify for nothing rather than
  /// guessing on the user's behalf.
  final Set<String> notifiableRuleIds;

  RuleNotificationPlan plan({
    required Rule rule,
    required RuleEvaluationResult result,
    required NotificationPreference preference,
    Set<String> alreadyNotifiedKeys = const <String>{},
  }) {
    // 1. The user's preference is authoritative and is honoured first, so a
    //    disabled rule can never notify through a later branch.
    switch (preference) {
      case NotificationPreference.noNotifications:
        return _plan(
          rule,
          result,
          NotificationDecision.suppressedByPreference,
          'the user has turned notifications off',
        );
      case NotificationPreference.allRuleNotifications:
        break;
      case NotificationPreference.importantOnly:
      case NotificationPreference.specificRulesOnly:
        if (!notifiableRuleIds.contains(rule.id)) {
          return _plan(
            rule,
            result,
            NotificationDecision.suppressedByPreference,
            'the rule is not in the user\'s notifiable set',
          );
        }
    }

    // 2. Missing or stale data is never reported as a match.
    if (result.isIndeterminate) {
      return _plan(
        rule,
        result,
        NotificationDecision.indeterminate,
        result.note ?? 'device state is not current',
      );
    }

    // 3. The condition is false.
    if (!result.isMatched) {
      return _plan(
        rule,
        result,
        NotificationDecision.notMatched,
        result.note ?? 'the condition does not hold',
      );
    }

    // 4. A repeated match inside the cooldown window stays visible in the app
    //    but must not notify again (FR-039, FR-040).
    if (!result.shouldNotify) {
      return _plan(
        rule,
        result,
        NotificationDecision.suppressedByCooldown,
        'the rule is cooling down',
      );
    }

    final key = result.interpretation?.id;
    if (key != null && alreadyNotifiedKeys.contains(key)) {
      return _plan(
        rule,
        result,
        NotificationDecision.duplicate,
        'this interpretation was already notified',
      );
    }

    return RuleNotificationPlan(
      decision: NotificationDecision.notify,
      reason: 'the condition holds on fresh data',
      ruleId: rule.id,
      title: rule.name,
      body: result.interpretation?.message,
      dedupeKey: key,
    );
  }

  RuleNotificationPlan _plan(
    Rule rule,
    RuleEvaluationResult result,
    NotificationDecision decision,
    String reason,
  ) {
    return RuleNotificationPlan(
      decision: decision,
      reason: reason,
      ruleId: rule.id,
      dedupeKey: result.interpretation?.id,
    );
  }
}
