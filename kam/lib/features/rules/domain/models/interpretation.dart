import 'rule.dart';

/// One observed fact that an interpretation is based on.
///
/// Exposing the basis satisfies SRS NFR-022's "Why am I seeing this?".
class InterpretationBasis {
  const InterpretationBasis({
    required this.metric,
    required this.description,
    this.formattedValue,
  });

  final RuleMetric metric;

  /// Human-readable description of the underlying observation, for example
  /// `Phone has been charging for 4h 08m`.
  final String description;

  /// The rendered observed value, for example `4h 08m`.
  final String? formattedValue;

  @override
  String toString() => 'InterpretationBasis(${metric.name}: $description)';
}

/// The output of an active rule.
///
/// An [Interpretation] is **never** an objective fact. It is a user-configured
/// statement about a possible meaning of observed device state, and it must be
/// presented with uncertainty language (SRS FR-030, FR-031, NFR-023, NFR-041).
class Interpretation {
  const Interpretation({
    required this.id,
    required this.ruleId,
    required this.ownerUserId,
    required this.pairId,
    required this.message,
    required this.basis,
    required this.producedAt,
    this.probabilityPercent,
    this.sourceCondition,
  });

  final String id;
  final String ruleId;

  /// The user whose rule produced this interpretation.
  final String ownerUserId;

  /// The pair the interpretation applies to.
  final String pairId;

  /// Rendered message. Must use uncertainty phrasing such as
  /// "There is a 70% possibility that ..." rather than "The person is ...".
  final String message;

  /// The user's configured percentage, if the rule defines one.
  ///
  /// This is **user-defined**, not measured. It is never a scientifically
  /// validated or ML-computed probability (SRS FR-030).
  final int? probabilityPercent;

  /// The observed facts this interpretation is based on.
  final List<InterpretationBasis> basis;

  /// When the rule became active, in UTC.
  final DateTime? producedAt;

  /// The condition that triggered this interpretation (NFR-022).
  final RuleCondition? sourceCondition;

  /// Interpretations are never facts.
  ///
  /// Kept as an explicit, always-false property so presentation code cannot
  /// accidentally treat an interpretation as a measurement.
  bool get isObjectiveFact => false;

  /// Whether a user-configured percentage is attached.
  bool get hasUserDefinedProbability => probabilityPercent != null;

  @override
  String toString() => 'Interpretation($id, "$message")';
}
