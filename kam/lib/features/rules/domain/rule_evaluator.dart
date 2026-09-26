import '../../../core/data/data_availability.dart';
import '../../../core/freshness/data_freshness.dart';
import '../../device_state/domain/models/device_state.dart';
import '../../device_state/domain/models/metric_value.dart';
import '../../location/domain/models/location_state.dart';
import 'models/interpretation.dart';
import 'models/rule.dart';
import 'rule_evaluation.dart';

/// Evaluates user-defined rules **on the device**.
///
/// This is the Spark-compatible replacement for the server-side rule evaluation
/// that ADR-002 originally reserved for Cloud Functions. It is safe to run on
/// the client because:
///
/// * every input is device state the signed-in user is already authorized to
///   read (the rules and the sharing gates decide that, not this class);
/// * the output is a *user-defined interpretation*, which carries no authority —
///   it grants no access and makes no claim about another person's data;
/// * nothing here needs a secret, an Admin credential or cross-user access.
///
/// The class is pure and deterministic: it reads no clock, no I/O and no
/// environment, so identical inputs always produce identical results and the
/// SRS NFR-018/NFR-033 determinism requirement is satisfied by construction.
class RuleEvaluator {
  const RuleEvaluator({
    this.partnerName = 'your partner',
    this.allowStaleData = false,
  });

  /// Substituted for the `{partnerName}` placeholder in a message template
  /// (FR-031). Never sourced from the partner's private profile document.
  final String partnerName;

  /// Whether a stale last-known value may still drive a rule.
  ///
  /// Defaults to `false`: a rule that fires on a stale value would present old
  /// data as if it were current (NFR-025). Callers may opt in per surface, in
  /// which case the result is still flagged [RuleEvaluationOutcome.staleData]
  /// and the interpretation keeps the stale provenance.
  final bool allowStaleData;

  /// Evaluates [rule] against [deviceState] (and [locationState] when the
  /// condition needs location-derived metrics).
  RuleEvaluationResult evaluate({
    required Rule rule,
    required DeviceState deviceState,
    required DateTime nowUtc,
    LocationState? locationState,
  }) {
    if (!rule.enabled) {
      return _result(
        rule,
        RuleEvaluationOutcome.disabled,
        nowUtc,
        note: 'rule is disabled',
      );
    }

    final condition = rule.condition;
    final resolved = _resolve(
      condition.metric,
      deviceState,
      locationState,
      nowUtc,
    );

    if (resolved == null) {
      return _result(
        rule,
        RuleEvaluationOutcome.insufficientData,
        nowUtc,
        note: 'no ${condition.metric.name} value is available',
      );
    }

    if (!resolved.hasValue) {
      return _result(
        rule,
        RuleEvaluationOutcome.insufficientData,
        nowUtc,
        note: '${condition.metric.name} is ${resolved.availability.name}',
      );
    }

    // `has remained in state for` combines two facts: the current state and how
    // long it has held. When the condition names a state metric, the duration
    // lives in a sibling metric, so resolve it before comparing.
    final probe =
        condition.operator == RuleOperator.hasRemainedInStateFor &&
            resolved.duration == null
        ? _withSiblingDuration(resolved, condition.metric, deviceState, nowUtc)
        : resolved;

    // A stale value must not silently drive a rule. Freshness is classified by
    // the metric's own policy, so a value that legitimately updates slowly
    // (last-known location) is judged against a slower policy (FR-047/FR-061).
    //
    // The gate applies to metrics that report a *snapshot* (battery, charging,
    // network, distance). It deliberately does not apply to metrics whose value
    // already describes age or availability, because those would otherwise be
    // unreachable — see [_MetricProbe.stalenessApplies].
    if (probe.stalenessApplies &&
        probe.freshness == DataFreshness.stale &&
        !allowStaleData) {
      return _result(
        rule,
        RuleEvaluationOutcome.staleData,
        nowUtc,
        note: '${condition.metric.name} is stale',
      );
    }

    if (!_conditionMatches(condition, probe)) {
      return _result(rule, RuleEvaluationOutcome.notMatched, nowUtc);
    }

    final interpretation = _buildInterpretation(
      rule: rule,
      condition: condition,
      probe: probe,
      nowUtc: nowUtc,
    );

    if (rule.isCoolingDownAt(nowUtc)) {
      return _result(
        rule,
        RuleEvaluationOutcome.coolingDown,
        nowUtc,
        interpretation: interpretation,
        note: 'condition holds but cooldown suppresses a notification',
      );
    }

    return _result(
      rule,
      RuleEvaluationOutcome.matched,
      nowUtc,
      interpretation: interpretation,
    );
  }

  /// Evaluates every rule in [rules], preserving input order.
  ///
  /// Useful for a dashboard that renders all of a user's rules at once.
  List<RuleEvaluationResult> evaluateAll({
    required Iterable<Rule> rules,
    required DeviceState deviceState,
    required DateTime nowUtc,
    LocationState? locationState,
  }) {
    return [
      for (final rule in rules)
        evaluate(
          rule: rule,
          deviceState: deviceState,
          nowUtc: nowUtc,
          locationState: locationState,
        ),
    ];
  }

  // ---------------------------------------------------------------------
  // Metric resolution
  // ---------------------------------------------------------------------

  /// Resolves a [RuleMetric] into a uniform probe, or `null` when the metric has
  /// no representation in the supplied state at all.
  _MetricProbe? _resolve(
    RuleMetric metric,
    DeviceState deviceState,
    LocationState? locationState,
    DateTime nowUtc,
  ) {
    switch (metric) {
      case RuleMetric.batteryPercentage:
        return _numeric(deviceState.batteryPercentage, nowUtc, 'Battery', '%');

      case RuleMetric.chargingState:
        return _state(deviceState.chargingState, nowUtc, 'Charging');

      case RuleMetric.chargingDuration:
        return _duration(
          deviceState.chargingDuration,
          nowUtc,
          'Charging duration',
        );

      case RuleMetric.networkStatus:
        return _state(deviceState.networkStatus, nowUtc, 'Network');

      case RuleMetric.offlineDuration:
      case RuleMetric.lastOnlineDuration:
        return _duration(
          deviceState.offlineDuration,
          nowUtc,
          'Last online',
          treatAsLastKnown: true,
        );

      case RuleMetric.lastActivityDuration:
        return _duration(deviceState.lastActivity, nowUtc, 'Last activity');

      case RuleMetric.deviceAvailability:
        return _state(deviceState.availability, nowUtc, 'Availability');

      case RuleMetric.distanceFromHomeKm:
        final location = locationState;
        if (location == null) return null;
        return _numeric(
          location.distanceFromHomeKm,
          nowUtc,
          'Distance from home',
          ' km',
        );

      case RuleMetric.homePresence:
        final location = locationState;
        if (location == null) return null;
        // Presence is a derived classification, not a measurement.
        return _enumProbe(
          location.presence,
          location.coordinates,
          nowUtc,
          'Presence',
        );

      case RuleMetric.locationAvailability:
        final location = locationState;
        if (location == null) {
          return _MetricProbe(
            availability: DataAvailability.unsupported,
            freshness: DataFreshness.unknown,
            stateName: 'unsupported',
            description: 'Location: unsupported',
          );
        }
        return _locationAvailability(location, nowUtc);

      case RuleMetric.locationAge:
        final location = locationState;
        if (location == null) return null;
        final age = location.coordinates.ageAt(nowUtc);
        if (age == null) {
          return _MetricProbe(
            availability: DataAvailability.unknown,
            freshness: DataFreshness.unknown,
            description: 'Location: unknown',
          );
        }
        return _MetricProbe(
          availability: DataAvailability.available,
          freshness: location.coordinates.freshnessAt(nowUtc),
          duration: age,
          description: 'Location age: ${age.inMinutes}m',
          // The value *is* an age, so it cannot itself be out of date.
          stalenessApplies: false,
        );
    }
  }

  /// The duration metric that measures how long [stateMetric] has held.
  RuleMetric? _durationMetricFor(RuleMetric stateMetric) {
    switch (stateMetric) {
      case RuleMetric.chargingState:
        return RuleMetric.chargingDuration;
      case RuleMetric.networkStatus:
      case RuleMetric.deviceAvailability:
        return RuleMetric.offlineDuration;
      case RuleMetric.batteryPercentage:
      case RuleMetric.chargingDuration:
      case RuleMetric.offlineDuration:
      case RuleMetric.lastOnlineDuration:
      case RuleMetric.lastActivityDuration:
      case RuleMetric.distanceFromHomeKm:
      case RuleMetric.homePresence:
      case RuleMetric.locationAvailability:
      case RuleMetric.locationAge:
        return null;
    }
  }

  /// Attaches the sibling duration metric so a `has remained in state for`
  /// condition can compare both the state and its duration.
  _MetricProbe _withSiblingDuration(
    _MetricProbe probe,
    RuleMetric stateMetric,
    DeviceState deviceState,
    DateTime nowUtc,
  ) {
    final durationMetric = _durationMetricFor(stateMetric);
    if (durationMetric == null) return probe;
    final durationProbe = _resolve(durationMetric, deviceState, null, nowUtc);
    final duration = durationProbe?.duration;
    if (duration == null) return probe;
    return _MetricProbe(
      availability: probe.availability,
      freshness: probe.freshness,
      description: probe.description,
      number: probe.number,
      duration: duration,
      stateName: probe.stateName,
    );
  }

  _MetricProbe _locationAvailability(LocationState location, DateTime nowUtc) {
    final coordinates = location.coordinates;
    final freshness = coordinates.freshnessAt(nowUtc);
    final String stateName;
    if (!coordinates.hasValue) {
      stateName = coordinates.availability == DataAvailability.unsupported
          ? 'unsupported'
          : 'unavailable';
    } else if (freshness == DataFreshness.stale) {
      stateName = 'stale';
    } else {
      stateName = 'available';
    }
    return _MetricProbe(
      availability: coordinates.availability,
      freshness: freshness,
      stateName: stateName,
      description: 'Location availability: $stateName',
      // The value is a freshness classification, so gating on staleness would
      // make the `stale` state impossible to match.
      stalenessApplies: false,
    );
  }

  /// Probe for a numeric metric.
  ///
  /// Accepts `MetricValue<dynamic>` so `MetricValue<int>` and
  /// `MetricValue<double>` share one path without boxing gymnastics.
  _MetricProbe _numeric(
    MetricValue<dynamic> metric,
    DateTime nowUtc,
    String label,
    String unit,
  ) {
    final value = metric.value;
    final hasNumber = metric.hasValue && value is num;
    return _MetricProbe(
      availability: metric.availability,
      freshness: metric.freshnessAt(nowUtc),
      number: hasNumber ? value : null,
      description: hasNumber
          ? '$label: ${_formatNumber(value)}$unit'
          : '$label: ${_availabilityLabel(metric.availability)}',
    );
  }

  /// Probe for a [Duration]-valued metric.
  _MetricProbe _duration(
    MetricValue<dynamic> metric,
    DateTime nowUtc,
    String label, {
    bool treatAsLastKnown = false,
  }) {
    final value = metric.value;
    final hasDuration = metric.hasValue && value is Duration;
    return _MetricProbe(
      availability: metric.availability,
      // "Last online" is inherently a last-known value: growing the duration
      // does not make the observation wrong, so it is not treated as stale on
      // the strength of its origin timestamp alone.
      freshness: treatAsLastKnown
          ? DataFreshness.recent
          : metric.freshnessAt(nowUtc),
      // A "since the last event" duration is just as true an hour later.
      stalenessApplies: !treatAsLastKnown,
      duration: hasDuration ? value : null,
      description: hasDuration
          ? '$label: ${_formatDuration(value)} ago'
          : '$label: ${_availabilityLabel(metric.availability)}',
    );
  }

  /// Probe for an enum-valued metric (charging state, network, availability).
  _MetricProbe _state(
    MetricValue<dynamic> metric,
    DateTime nowUtc,
    String label,
  ) {
    final value = metric.value;
    final name = value is Enum ? value.name : null;
    return _MetricProbe(
      availability: metric.availability,
      freshness: metric.freshnessAt(nowUtc),
      stateName: name,
      description: name != null
          ? '$label: $name'
          : '$label: ${_availabilityLabel(metric.availability)}',
    );
  }

  /// Probe for a derived enum whose freshness follows another metric.
  _MetricProbe _enumProbe(
    Enum value,
    MetricValue<dynamic> freshnessSource,
    DateTime nowUtc,
    String label,
  ) {
    return _MetricProbe(
      availability: freshnessSource.availability,
      freshness: freshnessSource.freshnessAt(nowUtc),
      stateName: value.name,
      description: '$label: ${value.name}',
    );
  }

  // ---------------------------------------------------------------------
  // Condition matching
  // ---------------------------------------------------------------------

  bool _conditionMatches(RuleCondition condition, _MetricProbe probe) {
    if (condition.operator == RuleOperator.hasRemainedInStateFor) {
      return _remainedInStateFor(condition, probe);
    }

    // State metrics compare by name; numeric and duration metrics compare by
    // magnitude. An operator that does not apply to the metric's kind cannot
    // match, and the caller surfaces that as "not matched" with a note rather
    // than silently succeeding.
    if (probe.stateName != null && probe.number == null) {
      return _matchState(condition, probe.stateName!);
    }
    if (probe.number != null) {
      return _matchNumber(condition, probe.number!);
    }
    if (probe.duration != null) {
      return _matchDuration(condition, probe.duration!);
    }
    return false;
  }

  bool _matchState(RuleCondition condition, String actual) {
    final expected = condition.stateValue;
    if (expected == null) return false;
    switch (condition.operator) {
      case RuleOperator.equalTo:
      case RuleOperator.isA:
        return actual == expected;
      case RuleOperator.notEqualTo:
      case RuleOperator.isNot:
        return actual != expected;
      // Magnitude operators have no meaning for a named state.
      case RuleOperator.greaterThan:
      case RuleOperator.greaterThanOrEqual:
      case RuleOperator.lessThan:
      case RuleOperator.lessThanOrEqual:
      case RuleOperator.hasRemainedInStateFor:
        return false;
    }
  }

  bool _matchNumber(RuleCondition condition, num actual) {
    final expected = condition.numericThreshold;
    if (expected == null) return false;
    switch (condition.operator) {
      case RuleOperator.equalTo:
      case RuleOperator.isA:
        return actual == expected;
      case RuleOperator.notEqualTo:
      case RuleOperator.isNot:
        return actual != expected;
      case RuleOperator.greaterThan:
        return actual > expected;
      case RuleOperator.greaterThanOrEqual:
        return actual >= expected;
      case RuleOperator.lessThan:
        return actual < expected;
      case RuleOperator.lessThanOrEqual:
        return actual <= expected;
      case RuleOperator.hasRemainedInStateFor:
        return false;
    }
  }

  bool _matchDuration(RuleCondition condition, Duration actual) {
    final expected = _thresholdDuration(condition);
    if (expected == null) return false;
    switch (condition.operator) {
      case RuleOperator.equalTo:
      case RuleOperator.isA:
        return actual == expected;
      case RuleOperator.notEqualTo:
      case RuleOperator.isNot:
        return actual != expected;
      case RuleOperator.greaterThan:
        return actual > expected;
      case RuleOperator.greaterThanOrEqual:
        return actual >= expected;
      case RuleOperator.lessThan:
        return actual < expected;
      case RuleOperator.lessThanOrEqual:
        return actual <= expected;
      case RuleOperator.hasRemainedInStateFor:
        return actual >= expected;
    }
  }

  /// `has remained in state for`: two facts must both hold — the metric is the
  /// expected state, and the duration it has been in that state meets the
  /// threshold.
  bool _remainedInStateFor(RuleCondition condition, _MetricProbe probe) {
    final expectedState = condition.stateValue;
    final required = _thresholdDuration(condition);
    if (expectedState == null || required == null) return false;

    // Either the probe already carries the duration (a duration metric) or the
    // condition names the state and the duration lives in a sibling metric.
    final actualDuration = probe.duration;
    if (actualDuration != null) {
      return _stateMatches(probe.stateName, expectedState) &&
          actualDuration >= required;
    }
    return false;
  }

  bool _stateMatches(String? actual, String expected) =>
      actual != null && actual == expected;

  /// A duration threshold is expressed either directly as a [Duration] or as a
  /// count of minutes in [RuleCondition.numericThreshold].
  Duration? _thresholdDuration(RuleCondition condition) {
    final direct = condition.durationThreshold;
    if (direct != null) return direct;
    final minutes = condition.numericThreshold;
    if (minutes == null) return null;
    return Duration(seconds: (minutes * 60).round());
  }

  // ---------------------------------------------------------------------
  // Interpretation building
  // ---------------------------------------------------------------------

  Interpretation _buildInterpretation({
    required Rule rule,
    required RuleCondition condition,
    required _MetricProbe probe,
    required DateTime nowUtc,
  }) {
    final probability = _probabilityOf(rule);
    return Interpretation(
      id: '${rule.id}@${nowUtc.toIso8601String()}',
      ruleId: rule.id,
      ownerUserId: rule.ownerUserId,
      pairId: rule.pairId,
      message: _message(rule, condition, probe, probability),
      probabilityPercent: probability,
      basis: [
        InterpretationBasis(
          metric: condition.metric,
          description: probe.description,
        ),
      ],
      producedAt: nowUtc,
      sourceCondition: condition,
    );
  }

  int? _probabilityOf(Rule rule) {
    for (final action in rule.actions) {
      if (action.type == RuleActionType.displayProbability) {
        return action.probabilityPercent;
      }
    }
    return null;
  }

  /// Renders the user-visible message.
  ///
  /// A configured percentage is always framed as a *possibility*, never as a
  /// measurement or a validated probability (FR-030, NFR-023, NFR-041).
  String _message(
    Rule rule,
    RuleCondition condition,
    _MetricProbe probe,
    int? probability,
  ) {
    final template = _messageTemplateOf(rule);
    final subject = template != null
        ? template.replaceAll('{partnerName}', partnerName)
        : '$partnerName matches "${rule.name}"';
    if (probability == null) return subject;
    return 'There is a $probability% possibility that $subject';
  }

  String? _messageTemplateOf(Rule rule) {
    for (final action in rule.actions) {
      final template = action.messageTemplate;
      if (template != null && template.isNotEmpty) return template;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------

  RuleEvaluationResult _result(
    Rule rule,
    RuleEvaluationOutcome outcome,
    DateTime nowUtc, {
    Interpretation? interpretation,
    String? note,
  }) {
    return RuleEvaluationResult(
      ruleId: rule.id,
      outcome: outcome,
      evaluatedAt: nowUtc,
      interpretation: interpretation,
      note: note,
    );
  }

  static String _availabilityLabel(DataAvailability availability) {
    switch (availability) {
      case DataAvailability.available:
        return 'available';
      case DataAvailability.unknown:
        return 'unknown';
      case DataAvailability.unsupported:
        return 'unsupported';
      case DataAvailability.unavailable:
        return 'unavailable';
      case DataAvailability.paused:
        return 'paused';
    }
  }

  static String _formatNumber(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static String _formatDuration(Duration value) {
    if (value.inMinutes < 1) return '${value.inSeconds}s';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours == 0) return '${value.inMinutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}

/// A uniform view of one resolved metric, so the comparison logic does not need
/// to know the metric's Dart type.
class _MetricProbe {
  const _MetricProbe({
    required this.availability,
    required this.freshness,
    required this.description,
    this.number,
    this.duration,
    this.stateName,
    this.stalenessApplies = true,
  });

  final DataAvailability availability;
  final DataFreshness freshness;

  /// Human-readable observed value, used as the interpretation's basis.
  final String description;

  final num? number;
  final Duration? duration;

  /// Enum name for state-valued metrics.
  final String? stateName;

  /// Whether a stale observation should block the evaluation.
  ///
  /// True for snapshot metrics. False for metrics whose value already *is* an
  /// age or an availability classification (`locationAvailability`,
  /// `locationAge`, `offlineDuration`), which must stay evaluable or a rule such
  /// as "tell me when the location is stale" could never fire.
  final bool stalenessApplies;

  bool get hasValue => availability == DataAvailability.available;
}
