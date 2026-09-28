import '../../../../core/freshness/data_freshness.dart';
import '../rule_draft.dart';
import '../rule_evaluation.dart';
import 'interpretation.dart';
import 'rule.dart';

/// One observed *fact* that contributed to a rule matching (SRS FR-045,
/// NFR-022).
///
/// A fact is what the app observed — never what the rule concluded. The
/// description comes from the Phase 13 engine's interpretation basis, so the
/// wording is produced once, in one place, and cannot drift between the engine
/// and the UI.
class ObservedFact {
  const ObservedFact({
    required this.metric,
    required this.description,
    this.formattedValue,
    this.observedAt,
  });

  /// The metric this fact belongs to.
  final RuleMetric metric;

  /// Human-readable description, for example `Charging duration: 4h 11m`.
  final String description;

  /// The rendered observed value, for example `4h 11m`.
  final String? formattedValue;

  /// When the fact was observed, in UTC. Never a device identifier or a
  /// coordinate.
  final DateTime? observedAt;

  factory ObservedFact.fromBasis(InterpretationBasis basis) => ObservedFact(
    metric: basis.metric,
    description: basis.description,
    formattedValue: basis.formattedValue,
    observedAt: basis.observedAt,
  );
}

/// How a rule's match state changed between the previous cycle and this one.
///
/// This is the structure Phase 16 needs to decide whether an alert should be
/// raised or resolved. It is tracked locally and never persisted here.
enum RuleTransition {
  /// The rule became satisfied in this cycle.
  becameMatched,

  /// The rule was already satisfied and still is. Repeating state updates do not
  /// produce a new event (SRS FR-039/FR-040 duplicate handling).
  stayedMatched,

  /// The rule was satisfied and no longer is.
  becameNotMatched,

  /// The rule was not satisfied before and still is not.
  stayedNotMatched,

  /// The rule could not be evaluated in this cycle (unknown, stale,
  /// unsupported, permission-denied, insufficient data or invalid).
  becameIndeterminate,

  /// The rule already could not be evaluated.
  stayedIndeterminate,
}

/// Whether [outcome] is a "cannot tell" outcome rather than a yes/no answer.
bool ruleOutcomeIsIndeterminate(RuleEvaluationOutcome outcome) => switch (outcome) {
  RuleEvaluationOutcome.matched ||
  RuleEvaluationOutcome.notMatched ||
  RuleEvaluationOutcome.coolingDown ||
  RuleEvaluationOutcome.disabled => false,
  RuleEvaluationOutcome.unknown ||
  RuleEvaluationOutcome.unsupported ||
  RuleEvaluationOutcome.permissionDenied ||
  RuleEvaluationOutcome.error ||
  RuleEvaluationOutcome.insufficientData ||
  RuleEvaluationOutcome.staleData => true,
};

/// The result of evaluating one rule: engine outcome plus presentation context.
///
/// It deliberately *wraps* the Phase 13 [RuleEvaluationResult] rather than
/// restating it, so the engine stays the single source of truth for whether a
/// condition matched, which inputs were stale and which rule version ran.
///
/// The three concepts the UI must never collapse are kept as separate fields:
///
/// * the observed **facts** — [facts];
/// * the user's **rule** — [rule] (and the condition summary rendered from it);
/// * the user's **interpretation** — [title] with [userDefinedProbability].
class InterpretationResult {
  const InterpretationResult({
    required this.rule,
    required this.evaluation,
    required this.type,
    required this.transition,
    this.title,
    this.userDefinedProbability,
    this.facts = const <ObservedFact>[],
    this.freshness = DataFreshness.unknown,
    this.observationTime,
    this.explanation,
  });

  /// The canonical rule that produced this result.
  final Rule rule;

  /// The authoritative Phase 13 evaluation.
  final RuleEvaluationResult evaluation;

  /// What kind of interpretation the user configured.
  final RuleOutputKind type;

  /// Change in match state since the previous cycle.
  final RuleTransition transition;

  /// The user's own interpretation wording (status text, message or probability
  /// subject). Never generated, never reworded by the app.
  final String? title;

  /// The user's own configured percentage, when the rule defines one.
  ///
  /// Always presented as "user-defined". It is never a measured, statistical or
  /// model-computed probability (SRS FR-030, NFR-023, NFR-041).
  final int? userDefinedProbability;

  /// The observed facts the interpretation is based on.
  final List<ObservedFact> facts;

  /// Freshness of the evidence behind this result.
  final DataFreshness freshness;

  /// When the evidence behind this result was observed, in UTC.
  ///
  /// This is when the **partner's device** observed the state the rule was
  /// evaluated against — not when we read it, and not the anchor of a single
  /// fact. A four-hour charging duration is anchored at charging start;
  /// reporting that anchor as "when this was observed" would describe a current
  /// result as hours old.
  ///
  /// Null when the evidence carries no time at all, in which case freshness is
  /// unknown and the UI must say so rather than imply it is current (STEP 14).
  final DateTime? observationTime;

  /// A calm, user-safe explanation. Set for outcomes that are not a plain match
  /// (unknown, stale, unsupported, permission-denied, insufficient data, error).
  /// Never contains an internal error code.
  final String? explanation;

  /// The engine outcome.
  RuleEvaluationOutcome get status => evaluation.outcome;

  /// The rule's identity, kept alongside its version for evaluation metadata
  /// (SRS FR-036: versioning is preserved).
  String get ruleId => rule.id;
  String get ruleName => rule.name;
  int get ruleVersion => rule.version;

  /// When the engine ran, in UTC.
  DateTime get evaluatedAt => evaluation.evaluatedAt;

  /// Whether the rule's condition holds on usable data (including a match that
  /// is inside its cooldown window).
  bool get isMatched => evaluation.isMatched;

  /// Whether the rule could not be evaluated at all.
  bool get isIndeterminate => evaluation.isIndeterminate;

  /// Whether the condition is definitively false.
  bool get isNotMatched => evaluation.outcome == RuleEvaluationOutcome.notMatched;

  /// Whether this cycle produced a *new* match — the only case Phase 16 should
  /// consider raising an alert for on transition.
  bool get isNewMatch => transition == RuleTransition.becameMatched;

  /// Whether a match is inside its cooldown window, so it stays visible but must
  /// not raise a new alert (SRS FR-039, FR-040).
  bool get isCoolingDown => evaluation.outcome == RuleEvaluationOutcome.coolingDown;

  /// Whether this result is based on explicitly permitted stale input.
  bool get isBasedOnStaleData =>
      evaluation.staleInputMetrics.isNotEmpty ||
      freshness == DataFreshness.stale;

  /// A user-defined probability is present and must be labelled as such.
  bool get hasUserDefinedProbability =>
      userDefinedProbability != null || evaluation.interpretation?.hasUserDefinedProbability == true;

  /// The rendered engine message, kept for the notification layer (SRS FR-031).
  ///
  /// The UI presents [title] plus an explicitly labelled probability instead, so
  /// a user-configured wording is never dressed up as a measured statement.
  String? get engineMessage => evaluation.interpretation?.message;

  @override
  String toString() =>
      'InterpretationResult(${rule.id}:v${rule.version}, ${evaluation.outcome.name}, '
      '${transition.name})';
}
