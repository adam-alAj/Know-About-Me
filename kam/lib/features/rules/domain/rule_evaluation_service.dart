import '../../../../core/freshness/data_freshness.dart';
import '../../device_state/domain/models/device_state_snapshot.dart';
import '../../device_state/domain/models/remote_device_state.dart';
import 'interpretation_builder.dart';
import 'models/interpretation_result.dart';
import 'models/rule.dart';
import 'partner_state_adapter.dart';
import 'rule_evaluation.dart';
import 'rule_evaluator.dart';

/// One completed pass of the evaluation pipeline (STEP 22, STEP 23).
///
/// A cycle is the unit of determinism: every rule in [results] was evaluated
/// against the single [snapshot] taken at [evaluatedAt], so two rules can never
/// disagree because they happened to read slightly different moments of state.
class RuleEvaluationCycle {
  const RuleEvaluationCycle({
    required this.results,
    required this.outcomes,
    required this.evaluatedAt,
    required this.hasPartnerState,
    this.snapshot,
  });

  /// A cycle with nothing to evaluate.
  ///
  /// Produced when the user has no active pair, or the partner has never
  /// published state. No rule is evaluated and **no transition is emitted**:
  /// losing sight of the partner is not evidence that their condition stopped
  /// holding, and Phase 16 must not read it as one (STEP 25, STEP 31).
  RuleEvaluationCycle.empty({required DateTime evaluatedAt})
    : results = const <InterpretationResult>[],
      outcomes = const <String, RuleEvaluationOutcome>{},
      evaluatedAt = evaluatedAt.toUtc(),
      hasPartnerState = false,
      snapshot = null;

  /// One result per evaluated (enabled) rule, in the order the rules were
  /// supplied.
  final List<InterpretationResult> results;

  /// The engine outcome for every evaluated rule, keyed by rule id.
  ///
  /// The caller feeds this back as the previous outcomes of the next cycle so
  /// transitions can be classified without the service holding hidden state.
  final Map<String, RuleEvaluationOutcome> outcomes;

  /// When this cycle ran, in UTC.
  final DateTime evaluatedAt;

  /// Whether an authorized partner snapshot was available.
  final bool hasPartnerState;

  /// The normalized snapshot every rule in this cycle was evaluated against.
  final DeviceStateSnapshot? snapshot;

  /// Results whose condition holds (including a match inside its cooldown).
  List<InterpretationResult> get active => List<InterpretationResult>.unmodifiable([
    for (final result in results)
      if (result.isMatched) result,
  ]);

  /// Results the engine could not decide: unknown, stale, unsupported,
  /// permission-denied, insufficient data or invalid.
  ///
  /// Kept separate from [active] on purpose. Presenting one of these as a match
  /// would be the exact false certainty STEP 13 and STEP 30 forbid.
  List<InterpretationResult> get unclear =>
      List<InterpretationResult>.unmodifiable([
        for (final result in results)
          if (result.isIndeterminate) result,
      ]);

  /// What the UI should show, in a deterministic order.
  ///
  /// Matches first (they are what the user asked to be told about), then the
  /// rules that could not be decided, each group sorted by rule name. Rules that
  /// were evaluated and are simply false are omitted: they add noise without
  /// adding information.
  List<InterpretationResult> get displayable {
    final ordered = <InterpretationResult>[...active, ...unclear];
    ordered.sort((a, b) {
      final byName = a.ruleName.toLowerCase().compareTo(b.ruleName.toLowerCase());
      return byName != 0 ? byName : a.ruleId.compareTo(b.ruleId);
    });
    return List<InterpretationResult>.unmodifiable(ordered);
  }

  /// Whether any rule became satisfied in this cycle.
  bool get hasNewMatch =>
      results.any((result) => result.transition == RuleTransition.becameMatched);

  /// Whether there is nothing at all to show.
  bool get isEmpty => results.isEmpty;

  @override
  String toString() =>
      'RuleEvaluationCycle(${results.length} rules, '
      'partnerState: $hasPartnerState)';
}

/// Runs the Phase 15 evaluation pipeline.
///
/// ```text
/// enabled rules + authorized partner state
///        ↓
/// one normalized snapshot
///        ↓
/// Phase 13 RuleEvaluator  (decides every match)
///        ↓
/// InterpretationBuilder   (adds user meaning and observed facts)
///        ↓
/// RuleEvaluationCycle
/// ```
///
/// The service is **stateless**: the previous outcomes are an argument, not a
/// field, so a cycle is a pure function of its inputs and is trivially testable.
/// It performs no I/O, touches no widget, calls no platform API, talks to no
/// model and sends no notification (STEP 22). It never fetches data itself — the
/// caller supplies state that was already obtained through the authorized
/// partner-state stream (STEP 24).
class RuleEvaluationService {
  const RuleEvaluationService({
    this.evaluator = const RuleEvaluator(),
    this.builder = const InterpretationBuilder(),
  });

  /// The Phase 13 engine. It remains the only component allowed to decide
  /// whether a rule's conditions are satisfied.
  final RuleEvaluator evaluator;

  /// Converts an engine result into user-facing meaning.
  final InterpretationBuilder builder;

  /// Evaluates every enabled rule against one snapshot of [partnerState].
  ///
  /// Disabled rules are filtered out **before** the engine runs, so a disabled
  /// rule can never produce an active interpretation (STEP 3, STEP 28). Deleted
  /// rules are simply absent from [rules], so they are no longer evaluated
  /// (STEP 27). A rule whose definition changed is a new version and is handled
  /// by [RuleEvaluator] using the version on the rule it is given (STEP 26).
  RuleEvaluationCycle evaluate({
    required Iterable<Rule> rules,
    required RemoteDeviceState? partnerState,
    required DateTime nowUtc,
    Map<String, RuleEvaluationOutcome> previousOutcomes =
        const <String, RuleEvaluationOutcome>{},
  }) {
    final now = nowUtc.toUtc();
    final state = partnerState;
    if (state == null) return RuleEvaluationCycle.empty(evaluatedAt: now);

    final enabled = <Rule>[
      for (final rule in rules)
        if (rule.enabled) rule,
    ];
    if (enabled.isEmpty) {
      return RuleEvaluationCycle(
        results: const <InterpretationResult>[],
        outcomes: const <String, RuleEvaluationOutcome>{},
        evaluatedAt: now,
        hasPartnerState: true,
      );
    }

    // One snapshot for the whole cycle, adapt once, evaluate once (STEP 23,
    // STEP 34).
    final snapshot = PartnerStateAdapter.adapt(state);
    final freshness = state.observationFreshnessAt(now);
    final evaluations = evaluator.evaluateAllSnapshot(
      rules: enabled,
      snapshot: snapshot,
      nowUtc: now,
    );

    final results = <InterpretationResult>[];
    final outcomes = <String, RuleEvaluationOutcome>{};
    for (var index = 0; index < enabled.length; index++) {
      final rule = enabled[index];
      final evaluation = evaluations[index];
      outcomes[rule.id] = evaluation.outcome;
      results.add(
        builder.build(
          rule: rule,
          evaluation: evaluation,
          transition: transitionFor(
            previous: previousOutcomes[rule.id],
            current: evaluation.outcome,
          ),
          nowUtc: now,
          freshness: freshness,
          evidenceTime: snapshot.collectedAt,
        ),
      );
    }

    return RuleEvaluationCycle(
      results: List<InterpretationResult>.unmodifiable(results),
      outcomes: Map<String, RuleEvaluationOutcome>.unmodifiable(outcomes),
      evaluatedAt: now,
      hasPartnerState: true,
      snapshot: snapshot,
    );
  }

  /// Classifies how a rule moved between two cycles (STEP 12).
  ///
  /// [previous] is `null` for a rule that has never been evaluated, so its first
  /// real match is still reported as new — which is what Phase 16 needs to raise
  /// an alert exactly once, and the same is *not* true for a rule that was
  /// already matched (STEP 11).
  static RuleTransition transitionFor({
    required RuleEvaluationOutcome? previous,
    required RuleEvaluationOutcome current,
  }) {
    final nowIndeterminate = ruleOutcomeIsIndeterminate(current);
    final nowMatched =
        current == RuleEvaluationOutcome.matched ||
        current == RuleEvaluationOutcome.coolingDown;

    if (previous == null) {
      if (nowIndeterminate) return RuleTransition.becameIndeterminate;
      // A cooling-down rule already matched before this cycle could watch it
      // (that is why it is cooling down), so it is a continuation, not a new
      // match — Phase 16 must not alert on it.
      if (current == RuleEvaluationOutcome.coolingDown) {
        return RuleTransition.stayedMatched;
      }
      // A rule that is simply false has not "changed"; it has never held.
      return nowMatched
          ? RuleTransition.becameMatched
          : RuleTransition.stayedNotMatched;
    }

    final wasIndeterminate = ruleOutcomeIsIndeterminate(previous);
    final wasMatched =
        previous == RuleEvaluationOutcome.matched ||
        previous == RuleEvaluationOutcome.coolingDown;

    if (nowIndeterminate) {
      return wasIndeterminate
          ? RuleTransition.stayedIndeterminate
          : RuleTransition.becameIndeterminate;
    }
    if (nowMatched) {
      // Repeated state updates while a condition keeps holding are not new
      // events (STEP 11).
      return wasMatched
          ? RuleTransition.stayedMatched
          : RuleTransition.becameMatched;
    }
    return wasMatched
        ? RuleTransition.becameNotMatched
        : RuleTransition.stayedNotMatched;
  }

  /// The freshness of the evidence a cycle was based on, for presentation.
  static DataFreshness freshnessOf(
    RuleEvaluationCycle cycle,
    DateTime nowUtc,
  ) {
    final snapshot = cycle.snapshot;
    if (snapshot == null) return DataFreshness.unknown;
    return FreshnessPolicy.standard.classifyAge(
      nowUtc.toUtc().difference(snapshot.collectedAt.toUtc()),
    );
  }
}
