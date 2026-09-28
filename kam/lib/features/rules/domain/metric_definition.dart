import 'models/rule.dart';

/// How a metric's threshold is entered, validated and displayed (SRS FR-027 –
/// FR-032).
///
/// This is the *editing* view of the closed `RuleMetric` vocabulary defined by
/// the Phase 13 Rule Engine. It adds no evaluation behaviour and no second rule
/// model: a metric definition only says which operators and values the builder
/// may offer so the UI can never construct an invalid `RuleCondition`.
enum RuleValueKind {
  /// A 0–100 percentage, for example battery percentage.
  percentage,

  /// A plain non-negative number, for example a distance in kilometres.
  number,

  /// An elapsed duration, entered in minutes or hours and normalized to a
  /// canonical [Duration] on save.
  duration,

  /// A closed set of named states, selected from a list rather than typed.
  state,
}

/// The unit a duration is entered in.
enum DurationUnit {
  minutes,
  hours;

  /// The canonical [Duration] for [value] in this unit.
  Duration toDuration(num value) => Duration(
    seconds: (value * (this == DurationUnit.hours ? 3600 : 60)).round(),
  );
}

/// One selectable state of a state metric.
///
/// [value] is the canonical string compared by the engine; [label] is the
/// user-facing wording. Keeping both in one place means the UI can never offer a
/// state the engine cannot match (SRS FR-032).
class RuleStateOption {
  const RuleStateOption(this.value, this.label);

  final String value;
  final String label;
}

/// The user-facing description of one observable metric.
class RuleMetricDefinition {
  const RuleMetricDefinition({
    required this.metric,
    required this.label,
    required this.valueKind,
    required this.allowedOperators,
    this.unitLabel,
    this.states = const <RuleStateOption>[],
    this.platformDependent = false,
  });

  /// The canonical metric.
  final RuleMetric metric;

  /// Human-readable name shown in the builder, for example "Charging duration".
  final String label;

  /// Which value editor to show.
  final RuleValueKind valueKind;

  /// Operators the builder may offer for this metric.
  ///
  /// The engine accepts more combinations than are meaningful to a person
  /// (`isA` on a number, for example); the builder deliberately offers only the
  /// ones that read correctly (SRS FR-028).
  final List<RuleOperator> allowedOperators;

  /// Unit suffix for number/percentage metrics, for example `%` or `km`.
  final String? unitLabel;

  /// Selectable states for [RuleValueKind.state].
  final List<RuleStateOption> states;

  /// Whether the metric depends on a platform capability that may be absent.
  ///
  /// The builder shows a short note for these metrics so a user is not
  /// surprised when the rule reports "unavailable" rather than "false"
  /// (SRS FR-068, FR-048).
  final bool platformDependent;

  /// The user-facing label for [value], or the raw value when unknown.
  String labelForState(String value) => states
      .firstWhere(
        (option) => option.value == value,
        orElse: () => RuleStateOption(value, value),
      )
      .label;

  /// The operator options, as `(operator, label)` pairs.
  List<(RuleOperator, String)> get operatorOptions => [
    for (final operator in allowedOperators) (operator, ruleOperatorLabel(operator)),
  ];
}

/// The numeric comparison operators, shared by every numeric metric.
const List<RuleOperator> numericRuleOperators = <RuleOperator>[
  RuleOperator.equalTo,
  RuleOperator.notEqualTo,
  RuleOperator.greaterThan,
  RuleOperator.greaterThanOrEqual,
  RuleOperator.lessThan,
  RuleOperator.lessThanOrEqual,
];

/// The operators that make sense for a named state.
const List<RuleOperator> stateRuleOperators = <RuleOperator>[
  RuleOperator.isA,
  RuleOperator.isNot,
];

/// Short, plain-language label for a [RuleOperator].
String ruleOperatorLabel(RuleOperator operator) => switch (operator) {
  RuleOperator.equalTo => 'is',
  RuleOperator.notEqualTo => 'is not',
  RuleOperator.greaterThan => 'is greater than',
  RuleOperator.greaterThanOrEqual => 'is at least',
  RuleOperator.lessThan => 'is less than',
  RuleOperator.lessThanOrEqual => 'is at most',
  RuleOperator.isA => 'is',
  RuleOperator.isNot => 'is not',
  RuleOperator.hasRemainedInStateFor => 'has remained in state for',
};

/// The closed catalogue of metrics the builder may offer (SRS FR-027).
///
/// Every entry is a metric the Phase 13 engine can actually resolve. Adding a
/// metric to `RuleMetric` without adding it here is caught by
/// `test/unit/rule_metric_definition_test.dart`, so the two cannot drift.
abstract final class RuleMetrics {
  static const RuleMetricDefinition batteryPercentage = RuleMetricDefinition(
    metric: RuleMetric.batteryPercentage,
    label: 'Battery percentage',
    valueKind: RuleValueKind.percentage,
    unitLabel: '%',
    allowedOperators: numericRuleOperators,
  );

  static const RuleMetricDefinition chargingState = RuleMetricDefinition(
    metric: RuleMetric.chargingState,
    label: 'Charging',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    states: [
      RuleStateOption('charging', 'Charging'),
      RuleStateOption('notCharging', 'Not charging'),
      RuleStateOption('fullyCharged', 'Fully charged'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition chargingDuration = RuleMetricDefinition(
    metric: RuleMetric.chargingDuration,
    label: 'Charging duration',
    valueKind: RuleValueKind.duration,
    allowedOperators: numericRuleOperators,
  );

  static const RuleMetricDefinition networkStatus = RuleMetricDefinition(
    metric: RuleMetric.networkStatus,
    label: 'Connection',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    states: [
      RuleStateOption('online', 'Online'),
      RuleStateOption('offline', 'Offline'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition networkType = RuleMetricDefinition(
    metric: RuleMetric.networkType,
    label: 'Connection type',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    states: [
      RuleStateOption('wifi', 'Wi-Fi'),
      RuleStateOption('mobile', 'Mobile data'),
      RuleStateOption('ethernet', 'Ethernet'),
      RuleStateOption('bluetooth', 'Bluetooth'),
      RuleStateOption('vpn', 'VPN'),
      RuleStateOption('none', 'No connection'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition internetAvailability = RuleMetricDefinition(
    metric: RuleMetric.internetAvailability,
    label: 'Internet access',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    states: [
      RuleStateOption('available', 'Available'),
      RuleStateOption('unavailable', 'Unavailable'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition offlineDuration = RuleMetricDefinition(
    metric: RuleMetric.offlineDuration,
    label: 'Offline duration',
    valueKind: RuleValueKind.duration,
    allowedOperators: numericRuleOperators,
  );

  static const RuleMetricDefinition lastOnlineDuration = RuleMetricDefinition(
    metric: RuleMetric.lastOnlineDuration,
    label: 'Time since last online',
    valueKind: RuleValueKind.duration,
    allowedOperators: numericRuleOperators,
  );

  static const RuleMetricDefinition screenState = RuleMetricDefinition(
    metric: RuleMetric.screenState,
    label: 'Screen',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    platformDependent: true,
    states: [
      RuleStateOption('on', 'On'),
      RuleStateOption('off', 'Off'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition lastActivityDuration = RuleMetricDefinition(
    metric: RuleMetric.lastActivityDuration,
    label: 'Time since last activity',
    valueKind: RuleValueKind.duration,
    allowedOperators: numericRuleOperators,
    platformDependent: true,
  );

  static const RuleMetricDefinition deviceAvailability = RuleMetricDefinition(
    metric: RuleMetric.deviceAvailability,
    label: 'Device availability',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    states: [
      RuleStateOption('available', 'Available'),
      RuleStateOption('unavailable', 'Not available'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition timeSinceLastAvailability =
      RuleMetricDefinition(
        metric: RuleMetric.timeSinceLastAvailability,
        label: 'Time since last confirmed availability',
        valueKind: RuleValueKind.duration,
        allowedOperators: numericRuleOperators,
      );

  static const RuleMetricDefinition distanceFromHomeKm = RuleMetricDefinition(
    metric: RuleMetric.distanceFromHomeKm,
    label: 'Distance from home',
    valueKind: RuleValueKind.number,
    unitLabel: 'km',
    allowedOperators: numericRuleOperators,
    platformDependent: true,
  );

  static const RuleMetricDefinition homePresence = RuleMetricDefinition(
    metric: RuleMetric.homePresence,
    label: 'Home presence',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    platformDependent: true,
    states: [
      RuleStateOption('atHome', 'At home'),
      RuleStateOption('nearHome', 'Near home'),
      RuleStateOption('awayFromHome', 'Away from home'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition locationAvailability = RuleMetricDefinition(
    metric: RuleMetric.locationAvailability,
    label: 'Location availability',
    valueKind: RuleValueKind.state,
    allowedOperators: stateRuleOperators,
    platformDependent: true,
    states: [
      RuleStateOption('available', 'Available'),
      RuleStateOption('unavailable', 'Unavailable'),
      RuleStateOption('unknown', 'Unknown'),
    ],
  );

  static const RuleMetricDefinition locationAge = RuleMetricDefinition(
    metric: RuleMetric.locationAge,
    label: 'Age of the last location reading',
    valueKind: RuleValueKind.duration,
    allowedOperators: numericRuleOperators,
    platformDependent: true,
  );

  /// Every definition, in the order the builder offers them.
  static const List<RuleMetricDefinition> all = <RuleMetricDefinition>[
    batteryPercentage,
    chargingState,
    chargingDuration,
    networkStatus,
    networkType,
    internetAvailability,
    offlineDuration,
    lastOnlineDuration,
    screenState,
    lastActivityDuration,
    deviceAvailability,
    timeSinceLastAvailability,
    distanceFromHomeKm,
    homePresence,
    locationAvailability,
    locationAge,
  ];

  /// The definition for [metric].
  ///
  /// The catalogue is exhaustive over `RuleMetric`; a missing entry is a
  /// programming error and is surfaced as such rather than silently degrading.
  static RuleMetricDefinition of(RuleMetric metric) => all.firstWhere(
    (definition) => definition.metric == metric,
    orElse: () => throw ArgumentError.value(
      metric,
      'metric',
      'No rule builder definition exists for this metric',
    ),
  );
}
