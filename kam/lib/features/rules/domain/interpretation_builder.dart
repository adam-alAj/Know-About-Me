import '../../../../core/freshness/data_freshness.dart';
import 'models/interpretation.dart';
import 'models/interpretation_result.dart';
import 'models/rule.dart';
import 'rule_draft.dart';
import 'rule_evaluation.dart';

/// What the user configured a rule to mean (SRS FR-029, FR-030).
///
/// The interpretation output kind of [rule], or [RuleOutputKind.status] when the
/// rule only carries an output this build does not render (a notification or
/// event action belongs to a later phase).
RuleOutputKind ruleOutputKindOf(Rule rule) {
  for (final action in rule.actions) {
    final kind = RuleOutputKind.fromActionType(action.type);
    if (kind != null) return kind;
  }
  return RuleOutputKind.status;
}

/// The user's own interpretation wording, verbatim.
///
/// The application never rewrites, expands or "improves" this text: it is the
/// authoritative meaning of the rule, and the interpretation layer's job is only
/// to present it as user-defined (STEP 8, STEP 9).
String? ruleInterpretationTextOf(Rule rule) {
  for (final action in rule.actions) {
    final text = action.messageTemplate?.trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

/// The user's configured percentage, or `null` when the rule defines none.
///
/// Always a *user-defined* value. It is never a measured, statistical or
/// model-computed probability (SRS FR-030, NFR-023, NFR-041).
int? ruleUserDefinedProbabilityOf(Rule rule) {
  for (final action in rule.actions) {
    if (action.type == RuleActionType.displayProbability) {
      return action.probabilityPercent;
    }
  }
  return null;
}

/// A calm, user-safe explanation for a non-match evaluation outcome.
///
/// Deliberately free of error codes, metric names, Firestore paths and device
/// identifiers (SRS NFR-045). It answers "why is there no answer?" without
/// implying that the condition was checked and found false (STEP 13, STEP 29).
String? interpretationExplanationFor(RuleEvaluationOutcome outcome) =>
    switch (outcome) {
      RuleEvaluationOutcome.unknown =>
        'Some of the information this rule needs is not available yet.',
      RuleEvaluationOutcome.staleData =>
        'This rule is based on information that is no longer current.',
      RuleEvaluationOutcome.unsupported =>
        'This device cannot report some of the information this rule needs.',
      RuleEvaluationOutcome.permissionDenied =>
        'Sharing for some of the information this rule needs is turned off.',
      RuleEvaluationOutcome.insufficientData =>
        'Some of the information this rule needs has not been shared.',
      RuleEvaluationOutcome.error => 'This rule could not be checked.',
      RuleEvaluationOutcome.matched ||
      RuleEvaluationOutcome.coolingDown ||
      RuleEvaluationOutcome.notMatched ||
      RuleEvaluationOutcome.disabled => null,
    };

/// Turns one Phase 13 [RuleEvaluationResult] into the structured Phase 15
/// [InterpretationResult] (STEP 2, STEP 4).
///
/// The builder is a pure, deterministic function of `(rule, evaluation,
/// transition)`. It decides nothing about whether a condition matched — that is
/// the engine's job and stays there (STEP 2). It contributes only:
///
/// * the user's own interpretation wording and output kind;
/// * the observed **facts** the engine recorded as the interpretation's basis;
/// * freshness and the newest observation time behind those facts;
/// * a calm explanation when the rule could not be evaluated.
///
/// It never generates a sentence about a person, never adds a conclusion beyond
/// the configured rule, and never upgrades an uncertain result into a certain
/// one (STEP 9, STEP 30, STEP 31).
class InterpretationBuilder {
  const InterpretationBuilder({
    this.freshnessPolicy = FreshnessPolicy.standard,
  });

  /// Policy used when the caller does not supply the snapshot's own freshness.
  final FreshnessPolicy freshnessPolicy;

  InterpretationResult build({
    required Rule rule,
    required RuleEvaluationResult evaluation,
    required RuleTransition transition,
    required DateTime nowUtc,
    DataFreshness? freshness,
    DateTime? evidenceTime,
  }) {
    final facts = <ObservedFact>[
      for (final basis
          in evaluation.interpretation?.basis ?? const <InterpretationBasis>[])
        ObservedFact.fromBasis(basis),
    ];
    final observationTime =
        evidenceTime?.toUtc() ?? _newestObservationTime(evaluation, facts);

    return InterpretationResult(
      rule: rule,
      evaluation: evaluation,
      type: ruleOutputKindOf(rule),
      transition: transition,
      title: ruleInterpretationTextOf(rule),
      userDefinedProbability: ruleUserDefinedProbabilityOf(rule),
      facts: List<ObservedFact>.unmodifiable(facts),
      freshness: _freshness(
        evaluation: evaluation,
        observationTime: observationTime,
        supplied: freshness,
        nowUtc: nowUtc,
      ),
      observationTime: observationTime,
      explanation: interpretationExplanationFor(evaluation.outcome),
    );
  }

  DataFreshness _freshness({
    required RuleEvaluationResult evaluation,
    required DateTime? observationTime,
    required DataFreshness? supplied,
    required DateTime nowUtc,
  }) {
    // The engine is authoritative about stale *input*: if it blocked or flagged
    // a stale metric, the result must say so regardless of what the caller
    // supplies (STEP 14).
    if (evaluation.outcome == RuleEvaluationOutcome.staleData ||
        evaluation.staleInputMetrics.isNotEmpty) {
      return DataFreshness.stale;
    }
    if (supplied != null) return supplied;
    final observed = observationTime;
    if (observed == null) return DataFreshness.unknown;
    return freshnessPolicy.classifyAge(
      nowUtc.toUtc().difference(observed.toUtc()),
    );
  }

  /// The newest observation behind the result, used only when the caller cannot
  /// supply the evidence time itself.
  ///
  /// The newest rather than the oldest: a long charging duration is anchored at
  /// charging start, and reporting that anchor as "when this was observed" would
  /// wrongly describe a current result as hours old.
  static DateTime? _newestObservationTime(
    RuleEvaluationResult evaluation,
    List<ObservedFact> facts,
  ) {
    DateTime? newest;
    for (final fact in facts) {
      final time = fact.observedAt;
      if (time == null) continue;
      if (newest == null || time.isAfter(newest)) newest = time;
    }
    for (final time in evaluation.inputObservationTimes.values) {
      if (newest == null || time.isAfter(newest)) newest = time;
    }
    return newest?.toUtc();
  }
}
