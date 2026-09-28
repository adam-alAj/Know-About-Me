import 'models/interpretation_result.dart';
import 'models/rule.dart';
import 'rule_evaluation.dart';
import 'rule_evaluation_service.dart';

/// Decides *when* a further evaluation is genuinely needed because time alone
/// can change an answer (STEP 35, STEP 36).
///
/// A rule such as "charging duration is at least 4 hours" becomes true at a
/// known instant even if no new device event arrives exactly then. Computing
/// that instant is far cheaper and far more precise than polling: the caller
/// arms **one** timer for the single earliest crossing across every enabled
/// rule, and re-plans after it fires.
///
/// Bounds (both deliberate):
///
/// * [minimumDelay] of one second, so a threshold that has just been passed
///   cannot produce a tight retry loop;
/// * [maximumDelay] of fifteen minutes, which doubles as a freshness
///   re-check — a result can legitimately turn `stale` purely with age, and
///   nothing else in the app needs to run more often than that. This is
///   bounded, not a polling loop: it is at most four local, I/O-free
///   evaluations per hour, and zero when no time-dependent rule is enabled.
///
/// Known limitation: a rule on `offlineDuration` is not planned here, because
/// that value is measured to the moment the partner published it rather than to
/// the last time the device was seen online. Such a rule still re-evaluates on
/// every incoming state update, which is exactly when the partner can extend the
/// figure. Everything else re-evaluates on state changes, rule changes and the
/// single scheduled tick.
abstract final class RuleReevaluationScheduler {
  /// Shortest delay the caller will ever be asked to wait.
  static const Duration minimumDelay = Duration(seconds: 1);

  /// Longest delay the caller will ever be asked to wait.
  static const Duration maximumDelay = Duration(minutes: 15);

  /// How long until the next time-driven re-evaluation, or `null` when nothing
  /// can change on its own.
  static Duration? nextDelay({
    required RuleEvaluationCycle cycle,
    required DateTime nowUtc,
  }) {
    if (!cycle.hasPartnerState) return null;
    final now = nowUtc.toUtc();
    Duration? earliest;
    for (final result in cycle.results) {
      final pending = _delayFor(result, cycle, now);
      if (pending == null) continue;
      if (earliest == null || pending < earliest) earliest = pending;
    }
    if (earliest == null) return null;
    if (earliest < minimumDelay) return minimumDelay;
    return earliest > maximumDelay ? maximumDelay : earliest;
  }

  /// Metrics whose value is exactly `now - anchor`, so the instant it will cross
  /// a threshold can be computed without re-reading anything.
  static const Set<RuleMetric> _growingMetrics = <RuleMetric>{
    RuleMetric.chargingDuration,
    RuleMetric.lastOnlineDuration,
    RuleMetric.lastActivityDuration,
    RuleMetric.locationAge,
    RuleMetric.timeSinceLastAvailability,
  };

  static Duration? _delayFor(
    InterpretationResult result,
    RuleEvaluationCycle cycle,
    DateTime now,
  ) {
    final outcome = result.status;
    // Only a definite answer can change because time passed. A rule the engine
    // could not decide is waiting for *data*, not for the clock (STEP 29).
    final matched =
        outcome == RuleEvaluationOutcome.matched ||
        outcome == RuleEvaluationOutcome.coolingDown;
    final notMatched = outcome == RuleEvaluationOutcome.notMatched;
    if (!matched && !notMatched) return null;

    final rule = result.rule;
    final conditions = rule.conditionGroup?.conditions ?? <RuleCondition>[
      rule.condition,
    ];

    Duration? soonest;
    for (final condition in conditions) {
      if (!_growingMetrics.contains(condition.metric)) continue;
      final threshold = _thresholdOf(condition);
      if (threshold == null) continue;
      final anchor = _anchorFor(condition.metric, cycle, result.evaluation);
      if (anchor == null) continue;

      final crossing = _crossingDelay(condition.operator, threshold, anchor, now);
      if (crossing == null) continue;
      if (crossing <= Duration.zero) continue;
      if (soonest == null || crossing < soonest) soonest = crossing;
    }
    return soonest;
  }

  /// The instant a growing metric is measured from.
  ///
  /// The engine already records that origin for most metrics in the
  /// evaluation's input observation times. Charging duration is the exception:
  /// the engine times it from the charging session start, which lives on the
  /// snapshot rather than on the probe.
  static DateTime? _anchorFor(
    RuleMetric metric,
    RuleEvaluationCycle cycle,
    RuleEvaluationResult evaluation,
  ) {
    if (metric == RuleMetric.chargingDuration) {
      final startedAt = cycle.snapshot?.battery?.chargingStartedAt;
      if (startedAt != null) return startedAt.toUtc();
    }
    return evaluation.inputObservationTimes[metric.name];
  }

  /// When the condition changes truth value, or `null` when it cannot.
  ///
  /// Only a condition that is currently false and grows towards true (the
  /// common `>=` case), or currently true and grows towards false (`<`), has a
  /// predictable crossing. `equals` on a continuously growing duration has no
  /// single crossing, so it is left to state-change driven evaluation.
  static Duration? _crossingDelay(
    RuleOperator operator,
    Duration threshold,
    DateTime anchor,
    DateTime now,
  ) {
    final elapsed = now.difference(anchor.toUtc());
    final untilThreshold = threshold - elapsed;
    switch (operator) {
      case RuleOperator.greaterThan:
        // Strictly greater flips one instant *after* the threshold.
        return untilThreshold + const Duration(seconds: 1);
      case RuleOperator.greaterThanOrEqual:
      case RuleOperator.hasRemainedInStateFor:
        return untilThreshold;
      case RuleOperator.lessThan:
        return untilThreshold;
      case RuleOperator.lessThanOrEqual:
        return untilThreshold + const Duration(seconds: 1);
      case RuleOperator.equalTo:
      case RuleOperator.isA:
      case RuleOperator.notEqualTo:
      case RuleOperator.isNot:
        return null;
    }
  }

  static Duration? _thresholdOf(RuleCondition condition) {
    final direct = condition.durationThreshold;
    if (direct != null) return direct;
    final minutes = condition.numericThreshold;
    if (minutes == null) return null;
    return Duration(seconds: (minutes * 60).round());
  }
}
