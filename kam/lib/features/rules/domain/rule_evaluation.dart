import 'models/interpretation.dart';

/// Why a rule evaluation reached the result it did.
///
/// The vocabulary is deliberately richer than a boolean because the SRS
/// (FR-048, FR-068, NFR-015, NFR-025) requires the application to distinguish
/// "the condition is not true" from "we cannot currently tell". Collapsing the
/// two would let the UI imply that a reassurance rule was evaluated when in
/// fact the underlying device state was never available.
enum RuleEvaluationOutcome {
  /// The condition holds and the rule may produce an interpretation.
  matched,

  /// The condition was evaluated against available data and does not hold.
  notMatched,

  /// Required observation is absent or genuinely unknown.
  unknown,

  /// The platform or capability cannot provide the required input.
  unsupported,

  /// A required permission is not granted.
  permissionDenied,

  /// A malformed rule or invalid input prevented safe evaluation.
  error,

  /// A metric the condition depends on is unknown, unsupported, unavailable or
  /// paused, so the condition could not be evaluated at all.
  ///
  /// This is *not* the same as [notMatched].
  insufficientData,

  /// The metric exists but its last observation is older than the freshness
  /// policy allows, so it must not be treated as current (NFR-025).
  staleData,

  /// The rule is switched off, so nothing is evaluated (FR-034).
  disabled,

  /// The condition holds, but the rule's own cooldown suppresses a new
  /// notification (FR-039, FR-040).
  coolingDown,
}

/// The outcome of evaluating one [Rule] against one device state.
///
/// Evaluation happens entirely on the device. This is the Spark-compatible
/// replacement for server-side rule evaluation: the inputs are device-state
/// facts the signed-in user is already authorized to read, so no trusted server
/// is required to compute the result (see `ADR-009` and
/// `docs/architecture/SPARK_ONLY_ARCHITECTURE.md`).
class RuleEvaluationResult {
  const RuleEvaluationResult({
    required this.ruleId,
    this.ruleVersion = 1,
    required this.outcome,
    required this.evaluatedAt,
    this.evaluationId,
    this.matchedConditions = const [],
    this.unknownConditions = const [],
    this.staleInputMetrics = const [],
    this.inputObservationTimes = const {},
    this.interpretation,
    this.note,
  });

  /// The rule this result belongs to.
  final String ruleId;

  /// Exact persisted rule definition evaluated.
  final int ruleVersion;

  final RuleEvaluationOutcome outcome;

  /// When the evaluation ran, in UTC.
  final DateTime evaluatedAt;

  /// Deterministic fingerprint for deduplicating repeat evaluation of the same
  /// rule definition and same input evidence. No identifiers or coordinates.
  final String? evaluationId;

  final List<int> matchedConditions;
  final List<int> unknownConditions;

  /// Stale inputs that were explicitly permitted by rule/caller policy.
  final List<String> staleInputMetrics;

  /// Observation timestamps keyed by metric name, normalized to UTC.
  final Map<String, DateTime> inputObservationTimes;

  /// The produced interpretation. Present for [RuleEvaluationOutcome.matched]
  /// and [RuleEvaluationOutcome.coolingDown], absent otherwise.
  ///
  /// An interpretation is never an objective fact (FR-030, NFR-023, NFR-041).
  final Interpretation? interpretation;

  /// Short, non-sensitive explanation for logs and the "why am I seeing this?"
  /// affordance (NFR-022). Never contains device identifiers or coordinates.
  final String? note;

  /// Whether the condition was satisfied by current, available data.
  bool get isMatched =>
      outcome == RuleEvaluationOutcome.matched ||
      outcome == RuleEvaluationOutcome.coolingDown;

  /// Whether a *new* notification should be raised.
  ///
  /// A cooling-down match still produces an interpretation for display, but
  /// must not notify again (FR-039).
  bool get shouldNotify => outcome == RuleEvaluationOutcome.matched;

  /// Whether the rule could not be evaluated because required data was missing
  /// or not current. The UI must present this as unknown/stale rather than as a
  /// satisfied or unsatisfied condition (FR-048).
  bool get isIndeterminate =>
      outcome == RuleEvaluationOutcome.insufficientData ||
      outcome == RuleEvaluationOutcome.staleData ||
      outcome == RuleEvaluationOutcome.unknown ||
      outcome == RuleEvaluationOutcome.unsupported ||
      outcome == RuleEvaluationOutcome.permissionDenied ||
      outcome == RuleEvaluationOutcome.error;

  @override
  String toString() =>
      'RuleEvaluationResult($ruleId, ${outcome.name}'
      '${note != null ? ', $note' : ''})';
}
