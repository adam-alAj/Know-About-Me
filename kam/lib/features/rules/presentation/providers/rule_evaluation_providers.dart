import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../device_state/domain/models/remote_device_state.dart';
import '../../../device_state/presentation/providers/sync_providers.dart';
import '../../domain/models/interpretation_result.dart';
import '../../domain/models/rule.dart';
import '../../domain/rule_evaluation.dart';
import '../../domain/rule_evaluation_service.dart';
import '../../domain/rule_reevaluation_scheduler.dart';
import 'rule_providers.dart';

/// The Phase 13 engine wrapped in the Phase 15 pipeline.
final ruleEvaluationServiceProvider = Provider<RuleEvaluationService>(
  (ref) => const RuleEvaluationService(),
);

/// What the interpretation section needs to render.
///
/// Deliberately small and derived: it holds results and their provenance, never
/// a second copy of rule or device state.
class RuleEvaluationState {
  const RuleEvaluationState({
    this.results = const <InterpretationResult>[],
    this.evaluatedAt,
    this.hasPartnerState = false,
    this.isLoading = false,
    this.errorMessage,
  });

  /// The rules — or the authorized partner state — are still being loaded.
  static const RuleEvaluationState loading = RuleEvaluationState(
    isLoading: true,
  );

  /// There is no authorized partner state, so nothing is evaluated
  /// (STEP 25: a disconnected, revoked or expired pair stops evaluation).
  static const RuleEvaluationState waiting = RuleEvaluationState();

  /// The rules could not be read.
  static RuleEvaluationState failed(String message) =>
      RuleEvaluationState(errorMessage: message);

  /// Interpretations to show, already ordered by [RuleEvaluationCycle].
  final List<InterpretationResult> results;

  /// When the cycle behind [results] ran, in UTC.
  final DateTime? evaluatedAt;

  /// Whether an authorized partner snapshot was available.
  final bool hasPartnerState;

  final bool isLoading;

  /// A calm, user-facing failure message. Never an error code.
  final String? errorMessage;

  bool get hasError => errorMessage != null;

  /// Rules whose condition currently holds.
  List<InterpretationResult> get matches => <InterpretationResult>[
    for (final result in results)
      if (result.isMatched) result,
  ];

  /// Rules the engine could not decide — shown so "nothing appeared" is
  /// explainable rather than mysterious.
  List<InterpretationResult> get unclear => <InterpretationResult>[
    for (final result in results)
      if (result.isIndeterminate) result,
  ];

  @override
  String toString() =>
      'RuleEvaluationState(${results.length} results, '
      'partnerState: $hasPartnerState, loading: $isLoading)';
}

/// Runs the evaluation cycle against the authorized partner state.
final ruleEvaluationProvider =
    NotifierProvider<RuleEvaluationController, RuleEvaluationState>(
      RuleEvaluationController.new,
    );

/// Owns the reactive evaluation cycle.
///
/// The controller is the *application-level coordinator* of STEP 22: it gathers
/// enabled rules, takes the partner state the app is already streaming, asks the
/// pure [RuleEvaluationService] for a cycle, and exposes the result. It holds
/// two pieces of state of its own:
///
/// * the previous outcome per rule, so a rule that stays satisfied is not
///   reported as a new match on every state update (STEP 11);
/// * one bounded [Timer], re-planned after every cycle, so a condition that time
///   alone can satisfy is still noticed (STEP 35, STEP 36).
///
/// It never reads Firestore, never calls a platform API, never sends a
/// notification and never touches a widget (STEP 22, STEP 33).
class RuleEvaluationController extends Notifier<RuleEvaluationState> {
  final Map<String, RuleEvaluationOutcome> _previousOutcomes =
      <String, RuleEvaluationOutcome>{};

  Timer? _timer;

  /// Guards a timer callback that a rebuild has already superseded.
  int _generation = 0;

  @override
  RuleEvaluationState build() {
    // Registered on every build; Riverpod runs it before recomputing, so no
    // timer outlives the inputs it was planned from.
    ref.onDispose(_cancelTimer);

    final rulesAsync = ref.watch(rulesControllerProvider);
    final partnerAsync = ref.watch(partnerDeviceStateProvider);
    final rules = rulesAsync.value;

    if (rules == null) {
      _cancelTimer();
      return rulesAsync.hasError
          ? RuleEvaluationState.failed('Your rules could not be loaded.')
          : RuleEvaluationState.loading;
    }
    if (partnerAsync.isLoading) {
      _cancelTimer();
      return RuleEvaluationState.loading;
    }

    return _evaluate(
      rules: rules,
      partnerState: partnerAsync.value?.state,
    );
  }

  /// Re-runs the cycle against the state already loaded.
  ///
  /// Triggered by the bounded time-threshold timer. It performs no I/O: the
  /// partner state is read from the stream provider's current value.
  void reevaluate() {
    state = _evaluate(
      rules: ref.read(rulesControllerProvider).value ?? const <Rule>[],
      partnerState: ref.read(partnerDeviceStateProvider).value?.state,
    );
  }

  RuleEvaluationState _evaluate({
    required List<Rule> rules,
    required RemoteDeviceState? partnerState,
  }) {
    // No authorized partner state: stop evaluating, and forget the previous
    // outcomes so a later reconnection cannot look like a fresh transition that
    // never happened (STEP 25).
    if (partnerState == null) {
      _cancelTimer();
      _previousOutcomes.clear();
      return RuleEvaluationState.waiting;
    }

    final cycle = ref
        .read(ruleEvaluationServiceProvider)
        .evaluate(
          rules: rules,
          partnerState: partnerState,
          nowUtc: ref.read(clockProvider).nowUtc(),
          previousOutcomes: _previousOutcomes,
        );

    _previousOutcomes
      ..clear()
      ..addAll(cycle.outcomes);
    _armTimer(cycle);

    return RuleEvaluationState(
      results: cycle.displayable,
      evaluatedAt: cycle.evaluatedAt,
      hasPartnerState: true,
    );
  }

  void _armTimer(RuleEvaluationCycle cycle) {
    _cancelTimer();
    final generation = _generation;
    final delay = RuleReevaluationScheduler.nextDelay(
      cycle: cycle,
      nowUtc: ref.read(clockProvider).nowUtc(),
    );
    if (delay == null) return;
    _timer = Timer(delay, () {
      if (generation != _generation) return;
      _timer = null;
      reevaluate();
    });
  }

  void _cancelTimer() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}
