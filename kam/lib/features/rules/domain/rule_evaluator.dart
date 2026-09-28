import '../../../core/data/data_availability.dart';
import '../../../core/freshness/data_freshness.dart';
import '../../device_state/domain/models/device_state.dart';
import '../../device_state/domain/models/metric_value.dart';
import '../../device_state/domain/models/device_state_snapshot.dart';
import '../../device_state/domain/models/battery_state.dart' as normalized;
import '../../device_state/domain/models/network_state.dart' as normalized;
import '../../device_state/domain/models/device_availability_evidence.dart';
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

  /// Canonical Phase 6–12 entry point. Callers must supply a snapshot they
  /// already obtained through the authorized state stream; this method never
  /// fetches or authorizes data itself.
  RuleEvaluationResult evaluateSnapshot({
    required Rule rule,
    required DeviceStateSnapshot snapshot,
    required DateTime nowUtc,
  }) {
    final battery = snapshot.battery;
    final network = snapshot.network;
    final activity = snapshot.activity;
    final location = snapshot.location;
    final lastActivityAt = activity?.lastObservedActivityAt;
    final state = DeviceState(
      deviceId: snapshot.deviceId,
      batteryPercentage: _fromObservation(battery?.percentage),
      chargingState: _mapCharging(battery?.chargingState),
      chargingDuration: _fromObservation(battery?.chargingDuration),
      networkStatus: _mapNetwork(network),
      availability: _mapAvailability(snapshot.availability),
      offlineDuration: _fromObservation(network?.offlineDuration),
      lastActivity: lastActivityAt == null
          ? const MetricValue<Duration>.unknown(source: 'activity')
          : MetricValue<Duration>.derived(
              value: nowUtc.toUtc().difference(lastActivityAt.toUtc()),
              observedAt: lastActivityAt,
              source: activity!.activityStatus.source ?? 'activity',
            ),
      generatedAt: snapshot.collectedAt,
    );
    LocationState? locationState;
    if (location != null) {
      final fix = location.location.value ?? location.lastKnownLocation.value;
      final point = fix == null
          ? _fromObservation<Coordinate>(null)
          : MetricValue<Coordinate>.observed(
              value: fix.coordinate,
              observedAt: fix.observedAt,
              source: fix.source ?? 'location',
              freshnessPolicy: FreshnessPolicy.location,
            );
      final distance = location.distanceFromHome;
      final distanceKm = _convertObservation<double, double>(
        distance,
        (metres) => metres / 1000,
        nowUtc,
        freshnessPolicy: FreshnessPolicy.location,
      );
      locationState = LocationState(
        coordinates: point,
        distanceFromHomeKm: distanceKm,
        presence: location.presence,
      );
    }
    return evaluate(
      rule: rule,
      deviceState: state,
      locationState: locationState,
      normalizedSnapshot: snapshot,
      nowUtc: nowUtc,
    );
  }

  static MetricValue<T> _fromObservation<T>(StateObservation<T>? observation) {
    if (observation == null) return MetricValue<T>.unknown();
    final value = observation.value;
    switch (observation.availability) {
      case CapabilityAvailability.available:
      case CapabilityAvailability.stale:
        if (value == null) return MetricValue<T>.unknown();
        return MetricValue<T>.observed(
          value: value,
          observedAt:
              observation.observedAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          source: observation.source ?? 'normalized_snapshot',
          freshnessPolicy: FreshnessPolicy.standard,
        );
      case CapabilityAvailability.unsupported:
        return MetricValue<T>.unsupported(source: 'normalized_snapshot');
      case CapabilityAvailability.unknown:
        return MetricValue<T>.unknown(source: 'normalized_snapshot');
      case CapabilityAvailability.unavailable:
      case CapabilityAvailability.permissionDenied:
      case CapabilityAvailability.serviceDisabled:
      case CapabilityAvailability.error:
        return MetricValue<T>.unavailable(
          source: observation.availability.name,
          observedAt: observation.observedAt,
        );
    }
  }

  static MetricValue<T> _convertObservation<S, T>(
    StateObservation<S>? observation,
    T Function(S value) convert,
    DateTime nowUtc, {
    FreshnessPolicy freshnessPolicy = FreshnessPolicy.standard,
  }) {
    if (observation == null || observation.value == null) {
      return MetricValue<T>.unknown();
    }
    if (observation.availability != CapabilityAvailability.available &&
        observation.availability != CapabilityAvailability.stale) {
      return _fromObservation<T>(null);
    }
    return MetricValue<T>.derived(
      value: convert(observation.value as S),
      observedAt: observation.observedAt ?? nowUtc,
      source: observation.source ?? 'normalized_snapshot',
      freshnessPolicy: freshnessPolicy,
    );
  }

  static MetricValue<ChargingState> _mapCharging(
    StateObservation<normalized.BatteryChargingState>? observation,
  ) {
    if (observation == null || observation.value == null) {
      return const MetricValue<ChargingState>.unknown();
    }
    final value = switch (observation.value!) {
      normalized.BatteryChargingState.charging => ChargingState.charging,
      normalized.BatteryChargingState.full => ChargingState.fullyCharged,
      normalized.BatteryChargingState.discharging => ChargingState.notCharging,
      normalized.BatteryChargingState.notCharging => ChargingState.notCharging,
      normalized.BatteryChargingState.unknown => ChargingState.unknown,
    };
    return MetricValue<ChargingState>.observed(
      value: value,
      observedAt:
          observation.observedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: observation.source ?? 'normalized_snapshot',
    );
  }

  static MetricValue<NetworkStatus> _mapNetwork(
    normalized.NetworkState? network,
  ) {
    if (network == null || network.status.value == null) {
      return const MetricValue<NetworkStatus>.unknown();
    }
    final value = switch (network.status.value!) {
      normalized.NetworkOnlineStatus.online =>
        switch (network.connectivity.value) {
          normalized.ConnectivityType.wifi => NetworkStatus.wifi,
          normalized.ConnectivityType.mobile => NetworkStatus.mobile,
          _ => NetworkStatus.online,
        },
      normalized.NetworkOnlineStatus.offline => NetworkStatus.offline,
      normalized.NetworkOnlineStatus.unknown => NetworkStatus.unknown,
    };
    return MetricValue<NetworkStatus>.observed(
      value: value,
      observedAt:
          network.status.observedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: network.status.source ?? 'normalized_snapshot',
    );
  }

  static MetricValue<DeviceAvailabilityState> _mapAvailability(
    DeviceAvailabilityEvidence? evidence,
  ) {
    final availability = evidence?.availability;
    final value = switch (availability) {
      CapabilityAvailability.available => DeviceAvailabilityState.active,
      CapabilityAvailability.stale => DeviceAvailabilityState.offline,
      CapabilityAvailability.unknown || null => DeviceAvailabilityState.unknown,
      _ => DeviceAvailabilityState.unknown,
    };
    if (availability != CapabilityAvailability.available &&
        availability != CapabilityAvailability.stale) {
      return const MetricValue<DeviceAvailabilityState>.unknown();
    }
    return MetricValue<DeviceAvailabilityState>.observed(
      value: value,
      observedAt:
          evidence?.lastConfirmedAvailableAt ??
          evidence?.observedAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: evidence?.source ?? 'normalized_snapshot',
    );
  }

  /// Evaluates [rule] against [deviceState] (and [locationState] when the
  /// condition needs location-derived metrics).
  RuleEvaluationResult evaluate({
    required Rule rule,
    required DeviceState deviceState,
    required DateTime nowUtc,
    LocationState? locationState,
    DeviceStateSnapshot? normalizedSnapshot,
  }) {
    if (!rule.enabled) {
      return _result(
        rule,
        RuleEvaluationOutcome.disabled,
        nowUtc,
        note: 'rule is disabled',
      );
    }
    final validation = rule.validate();
    if (validation.isNotEmpty) {
      return _result(
        rule,
        RuleEvaluationOutcome.error,
        nowUtc,
        note: validation.map((issue) => issue.code).join(', '),
      );
    }
    final group = rule.conditionGroup;
    final conditions = group?.conditions ?? [rule.condition];
    final results = [
      for (final condition in conditions)
        _evaluateCondition(
          rule: rule,
          condition: condition,
          deviceState: deviceState,
          locationState: locationState,
          nowUtc: nowUtc,
          normalizedSnapshot: normalizedSnapshot,
        ),
    ];
    final isAnd = group?.operator != RuleGroupOperator.any;
    final isMatch = isAnd
        ? results.every((result) => result.isMatched)
        : results.any((result) => result.isMatched);
    final definiteMiss = isAnd
        ? results.any(
            (result) => result.outcome == RuleEvaluationOutcome.notMatched,
          )
        : results.every(
            (result) => result.outcome == RuleEvaluationOutcome.notMatched,
          );
    final outcome = isMatch
        ? (rule.isCoolingDownAt(nowUtc)
              ? RuleEvaluationOutcome.coolingDown
              : RuleEvaluationOutcome.matched)
        : definiteMiss
        ? RuleEvaluationOutcome.notMatched
        : _aggregateIndeterminate(results);
    final matchedIndices = <int>[
      for (var i = 0; i < results.length; i++)
        if (results[i].isMatched) i,
    ];
    final unknownIndices = <int>[
      for (var i = 0; i < results.length; i++)
        if (results[i].isIndeterminate) i,
    ];
    final selected = isAnd
        ? results
        : results.where((result) => result.isMatched);
    final basis = [
      for (final result in selected)
        if (result.interpretation != null) ...result.interpretation!.basis,
    ];
    final interpretation = !isMatch
        ? null
        : group == null
        ? results.single.interpretation
        : _buildGroupedInterpretation(rule, basis, nowUtc);
    final timestamps = <String, DateTime>{};
    for (final result in results) {
      timestamps.addAll(result.inputObservationTimes);
    }
    final fingerprint = [
      '${rule.id}:v${rule.version}',
      group?.operator.name ?? 'single',
      for (var i = 0; i < conditions.length; i++)
        '${conditions[i].metric.name}:${conditions[i].operator.name}:'
            '${results[i].evaluationId}:${results[i].outcome.name}',
    ].join('#');
    return RuleEvaluationResult(
      ruleId: rule.id,
      ruleVersion: rule.version,
      outcome: outcome,
      evaluatedAt: nowUtc.toUtc(),
      evaluationId: fingerprint,
      matchedConditions: List.unmodifiable(matchedIndices),
      unknownConditions: List.unmodifiable(unknownIndices),
      staleInputMetrics: List.unmodifiable([
        for (final result in results) ...result.staleInputMetrics,
      ]),
      inputObservationTimes: Map.unmodifiable(timestamps),
      interpretation: interpretation,
      note: switch (outcome) {
        RuleEvaluationOutcome.coolingDown =>
          'condition holds but cooldown suppresses a notification',
        RuleEvaluationOutcome.unknown => 'required observation is unknown',
        RuleEvaluationOutcome.unsupported =>
          'required capability is unsupported',
        RuleEvaluationOutcome.permissionDenied =>
          'required observation permission is denied',
        RuleEvaluationOutcome.error => 'rule or observation is invalid',
        RuleEvaluationOutcome.staleData => 'required observation is stale',
        RuleEvaluationOutcome.insufficientData =>
          'required observation is unavailable or sharing is paused',
        _ => null,
      },
    );
  }

  RuleEvaluationOutcome _aggregateIndeterminate(
    List<RuleEvaluationResult> results,
  ) {
    for (final outcome in [
      RuleEvaluationOutcome.error,
      RuleEvaluationOutcome.staleData,
      RuleEvaluationOutcome.permissionDenied,
      RuleEvaluationOutcome.unsupported,
      RuleEvaluationOutcome.unknown,
      RuleEvaluationOutcome.insufficientData,
    ]) {
      if (results.any((result) => result.outcome == outcome)) return outcome;
    }
    return RuleEvaluationOutcome.unknown;
  }

  Interpretation _buildGroupedInterpretation(
    Rule rule,
    List<InterpretationBasis> basis,
    DateTime nowUtc,
  ) {
    final probability = _probabilityOf(rule);
    final message =
        _messageTemplateOf(rule)?.replaceAll('{partnerName}', partnerName) ??
        '$partnerName matches "${rule.name}"';
    return Interpretation(
      id:
          '${rule.id}:v${rule.version}:${rule.conditionGroup!.operator.name}:'
          '${rule.conditionGroup!.conditions.map(_conditionKey).join('|')}: '
          '${basis.map((item) => '${item.metric.name}@${item.observedAt?.toUtc().toIso8601String()}').join('|')}',
      ruleId: rule.id,
      ownerUserId: rule.ownerUserId,
      pairId: rule.pairId,
      message: probability == null
          ? message
          : 'There is a user-defined $probability% possibility that $message',
      probabilityPercent: probability,
      basis: List.unmodifiable(basis),
      producedAt: nowUtc.toUtc(),
    );
  }

  RuleEvaluationResult _evaluateCondition({
    required Rule rule,
    required RuleCondition condition,
    required DeviceState deviceState,
    required LocationState? locationState,
    required DateTime nowUtc,
    DeviceStateSnapshot? normalizedSnapshot,
  }) {
    final resolved = _resolve(
      condition.metric,
      deviceState,
      locationState,
      nowUtc,
      normalizedSnapshot,
    );
    if (resolved == null) {
      return _result(
        rule,
        RuleEvaluationOutcome.unknown,
        nowUtc,
        note: 'no ${condition.metric.name} value is available',
        inputMetric: condition.metric,
      );
    }
    if (!resolved.hasValue) {
      final unavailable =
          resolved.unavailableOutcome ??
          switch (resolved.availability) {
            DataAvailability.unsupported => RuleEvaluationOutcome.unsupported,
            DataAvailability.unknown => RuleEvaluationOutcome.unknown,
            DataAvailability.unavailable ||
            DataAvailability.paused => RuleEvaluationOutcome.insufficientData,
            DataAvailability.available => RuleEvaluationOutcome.error,
          };
      return _result(
        rule,
        unavailable,
        nowUtc,
        note: '${condition.metric.name} is ${resolved.availability.name}',
        inputMetric: condition.metric,
        inputObservedAt: resolved.observedAt,
        evaluationFingerprint: _probeFingerprint(condition.metric, resolved),
      );
    }
    if (resolved.stalenessApplies &&
        resolved.freshness == DataFreshness.unknown) {
      return _result(
        rule,
        RuleEvaluationOutcome.unknown,
        nowUtc,
        note: '${condition.metric.name} has no observation timestamp',
        inputMetric: condition.metric,
        evaluationFingerprint: _probeFingerprint(condition.metric, resolved),
      );
    }
    final probe =
        condition.operator == RuleOperator.hasRemainedInStateFor &&
            resolved.duration == null
        ? _withSiblingDuration(resolved, condition.metric, deviceState, nowUtc)
        : resolved;
    if (condition.operator == RuleOperator.hasRemainedInStateFor &&
        probe.duration == null) {
      return _result(
        rule,
        normalizedSnapshot == null
            ? RuleEvaluationOutcome.insufficientData
            : RuleEvaluationOutcome.unknown,
        nowUtc,
        note: 'the state duration is unavailable',
        inputMetric: condition.metric,
        inputObservedAt: probe.observedAt,
        evaluationFingerprint: _probeFingerprint(condition.metric, probe),
      );
    }
    final staleInput =
        probe.stalenessApplies && probe.freshness == DataFreshness.stale;
    if (staleInput && !allowStaleData && !rule.allowStaleData) {
      return _result(
        rule,
        RuleEvaluationOutcome.staleData,
        nowUtc,
        note: '${condition.metric.name} is stale',
        inputMetric: condition.metric,
        inputObservedAt: probe.observedAt,
        evaluationFingerprint: _probeFingerprint(condition.metric, probe),
        staleInputMetrics: [condition.metric.name],
      );
    }
    if (!_conditionMatches(condition, probe)) {
      return _result(
        rule,
        RuleEvaluationOutcome.notMatched,
        nowUtc,
        inputMetric: condition.metric,
        inputObservedAt: probe.observedAt,
        evaluationFingerprint: _probeFingerprint(condition.metric, probe),
      );
    }
    final interpretation = _buildInterpretation(
      rule: rule,
      condition: condition,
      probe: probe,
      nowUtc: nowUtc,
    );
    final coolingDown = rule.isCoolingDownAt(nowUtc);
    return _result(
      rule,
      coolingDown
          ? RuleEvaluationOutcome.coolingDown
          : RuleEvaluationOutcome.matched,
      nowUtc,
      interpretation: interpretation,
      note: coolingDown
          ? 'condition holds but cooldown suppresses a notification'
          : null,
      inputMetric: condition.metric,
      inputObservedAt: probe.observedAt,
      evaluationFingerprint: _probeFingerprint(condition.metric, probe),
      staleInputMetrics: staleInput ? [condition.metric.name] : const [],
    );
  }

  static String _conditionKey(RuleCondition condition) =>
      '${condition.metric.name}:${condition.operator.name}:'
      '${condition.numericThreshold ?? ''}:${condition.stateValue ?? ''}:'
      '${condition.durationThreshold?.inMicroseconds ?? ''}';

  static String _probeFingerprint(RuleMetric metric, _MetricProbe probe) {
    final observationTime =
        probe.observedAt?.toUtc().toIso8601String() ?? 'no-time';
    const elapsedMetrics = {
      RuleMetric.offlineDuration,
      RuleMetric.lastOnlineDuration,
      RuleMetric.lastActivityDuration,
      RuleMetric.locationAge,
      RuleMetric.timeSinceLastAvailability,
    };
    return elapsedMetrics.contains(metric)
        ? '${metric.name}@$observationTime'
        : '${metric.name}:${probe.description}@$observationTime';
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

  /// Evaluates all rules against one already-authorized Phase 6–12 snapshot.
  /// The exact same immutable snapshot is reused for every rule.
  List<RuleEvaluationResult> evaluateAllSnapshot({
    required Iterable<Rule> rules,
    required DeviceStateSnapshot snapshot,
    required DateTime nowUtc,
  }) => [
    for (final rule in rules)
      evaluateSnapshot(rule: rule, snapshot: snapshot, nowUtc: nowUtc),
  ];

  // ---------------------------------------------------------------------
  // Metric resolution
  // ---------------------------------------------------------------------

  /// Resolves a [RuleMetric] into a uniform probe, or `null` when the metric has
  /// no representation in the supplied state at all.
  _MetricProbe? _resolve(
    RuleMetric metric,
    DeviceState deviceState,
    LocationState? locationState,
    DateTime nowUtc, [
    DeviceStateSnapshot? normalizedSnapshot,
  ]) {
    if (normalizedSnapshot != null) {
      final normalizedProbe = _resolveNormalized(
        metric,
        normalizedSnapshot,
        nowUtc,
      );
      if (normalizedProbe != null) return normalizedProbe;
    }
    switch (metric) {
      case RuleMetric.batteryPercentage:
        return _numeric(deviceState.batteryPercentage, nowUtc, 'Battery', '%');

      case RuleMetric.chargingState:
        return _state(deviceState.chargingState, nowUtc, 'Charging');

      case RuleMetric.networkType:
      case RuleMetric.internetAvailability:
      case RuleMetric.screenState:
        return null;

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
          observedAt: location.coordinates.observedAt,
          duration: age,
          description: 'Location age: ${age.inMinutes}m',
          // The value *is* an age, so it cannot itself be out of date.
          stalenessApplies: false,
        );

      case RuleMetric.timeSinceLastAvailability:
        return null;
    }
  }

  _MetricProbe? _resolveNormalized(
    RuleMetric metric,
    DeviceStateSnapshot snapshot,
    DateTime nowUtc,
  ) {
    switch (metric) {
      case RuleMetric.batteryPercentage:
        return _observationProbe(
          snapshot.battery?.percentage,
          nowUtc,
          'Battery',
          unit: '%',
        );
      case RuleMetric.chargingState:
        return _observationProbe(
          snapshot.battery?.chargingState,
          nowUtc,
          'Charging',
        );
      case RuleMetric.chargingDuration:
        return _observationProbe(
          snapshot.battery?.chargingDuration,
          nowUtc,
          'Charging duration',
        );
      case RuleMetric.networkType:
        return _observationProbe(
          snapshot.network?.connectivity,
          nowUtc,
          'Network type',
        );
      case RuleMetric.internetAvailability:
        return _observationProbe(
          snapshot.network?.internet,
          nowUtc,
          'Internet',
        );
      case RuleMetric.networkStatus:
        return _observationProbe(
          snapshot.network?.status,
          nowUtc,
          'Network status',
        );
      case RuleMetric.offlineDuration:
        return _observationProbe(
          snapshot.network?.offlineDuration,
          nowUtc,
          'Offline duration',
        );
      case RuleMetric.lastOnlineDuration:
        final lastOnlineAt = snapshot.network?.lastOnlineAt;
        if (lastOnlineAt == null) {
          return const _MetricProbe(
            availability: DataAvailability.unknown,
            freshness: DataFreshness.unknown,
            description: 'Last online: unknown',
          );
        }
        final elapsed = nowUtc.toUtc().difference(lastOnlineAt.toUtc());
        return _MetricProbe(
          availability: DataAvailability.available,
          freshness: DataFreshness.recent,
          duration: elapsed,
          observedAt: lastOnlineAt,
          description: 'Last online: ${_formatDuration(elapsed)} ago',
          stalenessApplies: false,
        );
      case RuleMetric.lastActivityDuration:
        final activityAt = snapshot.activity?.lastObservedActivityAt;
        if (activityAt == null) {
          return _MetricProbe(
            availability: snapshot.activity == null
                ? DataAvailability.unknown
                : _mapAvailabilityValue(
                    snapshot.activity!.activityStatus.availability,
                  ),
            freshness: DataFreshness.unknown,
            description: 'Last activity: unknown',
            unavailableOutcome: snapshot.activity == null
                ? RuleEvaluationOutcome.unknown
                : _outcomeFor(snapshot.activity!.activityStatus.availability),
          );
        }
        final activityAge = nowUtc.toUtc().difference(activityAt.toUtc());
        return _MetricProbe(
          availability: DataAvailability.available,
          freshness: DataFreshness.recent,
          duration: activityAge,
          observedAt: activityAt,
          description: 'Last activity: ${_formatDuration(activityAge)} ago',
          stalenessApplies: false,
        );
      case RuleMetric.screenState:
        return _observationProbe(
          snapshot.activity?.screenState,
          nowUtc,
          'Screen',
        );
      case RuleMetric.deviceAvailability:
        final evidence = snapshot.availability;
        if (evidence == null) {
          return const _MetricProbe(
            availability: DataAvailability.unknown,
            freshness: DataFreshness.unknown,
            description: 'Availability: unknown',
          );
        }
        final status = evidence.availability;
        if (status == CapabilityAvailability.available ||
            status == CapabilityAvailability.stale) {
          return _MetricProbe(
            availability: DataAvailability.available,
            freshness: evidence.freshnessAt(nowUtc),
            stateName: status.name,
            observedAt:
                evidence.lastConfirmedAvailableAt ?? evidence.observedAt,
            description: 'Availability: ${status.name}',
            stalenessApplies: status != CapabilityAvailability.stale,
          );
        }
        return _MetricProbe(
          availability: _mapAvailabilityValue(status),
          freshness: evidence.freshnessAt(nowUtc),
          stateName: status.name,
          observedAt: evidence.observedAt,
          description: 'Availability: ${status.name}',
          unavailableOutcome: _outcomeFor(status),
        );
      case RuleMetric.timeSinceLastAvailability:
        final evidence = snapshot.availability;
        final confirmedAt = evidence?.lastConfirmedAvailableAt;
        if (confirmedAt == null) {
          return _MetricProbe(
            availability:
                evidence == null ||
                    evidence.availability == CapabilityAvailability.unknown
                ? DataAvailability.unknown
                : _mapAvailabilityValue(evidence.availability),
            freshness: DataFreshness.unknown,
            observedAt: evidence?.observedAt,
            description: 'Time since last confirmed availability: unknown',
            unavailableOutcome: evidence == null
                ? RuleEvaluationOutcome.unknown
                : _outcomeFor(evidence.availability),
          );
        }
        final elapsed = nowUtc.toUtc().difference(confirmedAt.toUtc());
        return _MetricProbe(
          availability: DataAvailability.available,
          freshness: DataFreshness.recent,
          duration: elapsed,
          observedAt: confirmedAt,
          description:
              'Time since last confirmed availability: ${_formatDuration(elapsed)}',
          stalenessApplies: false,
        );
      case RuleMetric.distanceFromHomeKm:
        final observation = snapshot.location?.distanceFromHome;
        if (observation == null) return null;
        final probe = _observationProbe(
          observation,
          nowUtc,
          'Distance from home',
          unit: ' m',
          freshnessPolicy: FreshnessPolicy.location,
        );
        if (probe.number != null) {
          return _MetricProbe(
            availability: probe.availability,
            freshness: probe.freshness,
            number: probe.number! / 1000,
            observedAt: probe.observedAt,
            description:
                'Distance from home: ${_formatNumber(probe.number! / 1000)} km',
            unavailableOutcome: probe.unavailableOutcome,
          );
        }
        return probe;
      case RuleMetric.homePresence:
        final location = snapshot.location;
        if (location == null) return null;
        if (location.presence == HomePresence.unknown) {
          return const _MetricProbe(
            availability: DataAvailability.unknown,
            freshness: DataFreshness.unknown,
            description: 'Home presence: unknown',
          );
        }
        return _MetricProbe(
          availability: DataAvailability.available,
          freshness: location.freshnessAt(nowUtc),
          stateName: location.presence.name,
          observedAt:
              location.location.observedAt ??
              location.lastKnownLocation.observedAt,
          description: 'Home presence: ${location.presence.name}',
        );
      case RuleMetric.locationAvailability:
        final location = snapshot.location;
        if (location == null) return null;
        final availability = location.location.availability;
        final value = availability.name;
        final canClassify =
            availability == CapabilityAvailability.available ||
            availability == CapabilityAvailability.stale;
        return _MetricProbe(
          availability: canClassify
              ? DataAvailability.available
              : _mapAvailabilityValue(availability),
          freshness: location.freshnessAt(nowUtc),
          stateName: value,
          observedAt:
              location.location.observedAt ??
              location.lastKnownLocation.observedAt,
          description: 'Location availability: $value',
          stalenessApplies: false,
          unavailableOutcome: canClassify ? null : _outcomeFor(availability),
        );
      case RuleMetric.locationAge:
        final location = snapshot.location;
        if (location == null) return null;
        final fix = location.location.value ?? location.lastKnownLocation.value;
        if (fix == null) {
          return _MetricProbe(
            availability: _mapAvailabilityValue(location.location.availability),
            freshness: DataFreshness.unknown,
            description: 'Location age: unavailable',
            unavailableOutcome: _outcomeFor(location.location.availability),
          );
        }
        final age = nowUtc.toUtc().difference(fix.observedAt.toUtc());
        return _MetricProbe(
          availability: DataAvailability.available,
          freshness: location.freshnessAt(nowUtc),
          duration: age,
          observedAt: fix.observedAt,
          description: 'Location age: ${_formatDuration(age)}',
          stalenessApplies: false,
        );
    }
  }

  _MetricProbe _observationProbe<T>(
    StateObservation<T>? observation,
    DateTime nowUtc,
    String label, {
    String unit = '',
    FreshnessPolicy freshnessPolicy = FreshnessPolicy.standard,
  }) {
    if (observation == null) {
      return _MetricProbe(
        availability: DataAvailability.unknown,
        freshness: DataFreshness.unknown,
        description: '$label: unknown',
      );
    }
    final value = observation.value;
    final status = observation.availability;
    final isAvailable =
        value != null &&
        (status == CapabilityAvailability.available ||
            status == CapabilityAvailability.stale);
    final availability = isAvailable
        ? DataAvailability.available
        : _mapAvailabilityValue(status);
    final stateName = value is Enum
        ? value.name
        : value is String
        ? value
        : null;
    final number = value is num ? value : null;
    final duration = value is Duration ? value : null;
    final freshness = status == CapabilityAvailability.stale
        ? DataFreshness.stale
        : observation.freshnessAt(nowUtc, freshnessPolicy);
    final isUnknownEnum = stateName == 'unknown';
    final effectiveAvailability = isUnknownEnum
        ? DataAvailability.unknown
        : availability;
    final descriptionValue =
        stateName ??
        (number == null
            ? duration == null
                  ? null
                  : _formatDuration(duration)
            : '${_formatNumber(number)}$unit');
    return _MetricProbe(
      availability: effectiveAvailability,
      freshness: freshness,
      stateName: stateName,
      number: number,
      duration: duration,
      observedAt: observation.observedAt,
      description: descriptionValue == null
          ? '$label: ${status.name}'
          : '$label: $descriptionValue',
      unavailableOutcome: isUnknownEnum
          ? RuleEvaluationOutcome.unknown
          : isAvailable
          ? null
          : _outcomeFor(status),
    );
  }

  static DataAvailability _mapAvailabilityValue(
    CapabilityAvailability status,
  ) => switch (status) {
    CapabilityAvailability.available ||
    CapabilityAvailability.stale => DataAvailability.available,
    CapabilityAvailability.unknown => DataAvailability.unknown,
    CapabilityAvailability.unsupported => DataAvailability.unsupported,
    _ => DataAvailability.unavailable,
  };

  static RuleEvaluationOutcome _outcomeFor(CapabilityAvailability status) =>
      switch (status) {
        CapabilityAvailability.available => RuleEvaluationOutcome.matched,
        CapabilityAvailability.stale => RuleEvaluationOutcome.staleData,
        CapabilityAvailability.unknown => RuleEvaluationOutcome.unknown,
        CapabilityAvailability.unsupported => RuleEvaluationOutcome.unsupported,
        CapabilityAvailability.permissionDenied =>
          RuleEvaluationOutcome.permissionDenied,
        CapabilityAvailability.error => RuleEvaluationOutcome.error,
        CapabilityAvailability.unavailable ||
        CapabilityAvailability.serviceDisabled =>
          RuleEvaluationOutcome.insufficientData,
      };

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
      case RuleMetric.networkType:
      case RuleMetric.internetAvailability:
      case RuleMetric.screenState:
      case RuleMetric.homePresence:
      case RuleMetric.locationAvailability:
      case RuleMetric.locationAge:
      case RuleMetric.timeSinceLastAvailability:
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
      observedAt: probe.observedAt,
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
      observedAt: coordinates.observedAt,
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
      observedAt: metric.observedAt,
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
      observedAt: metric.observedAt,
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
    final isUnknown = name == 'unknown';
    return _MetricProbe(
      availability: isUnknown ? DataAvailability.unknown : metric.availability,
      freshness: metric.freshnessAt(nowUtc),
      observedAt: metric.observedAt,
      stateName: isUnknown ? null : name,
      description: name != null
          ? '$label: $name'
          : '$label: ${_availabilityLabel(metric.availability)}',
      unavailableOutcome: isUnknown ? RuleEvaluationOutcome.unknown : null,
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
      observedAt: freshnessSource.observedAt,
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
      id:
          '${rule.id}:v${rule.version}:${_conditionKey(condition)}:'
          '${probe.observedAt?.toUtc().toIso8601String() ?? 'no-time'}',
      ruleId: rule.id,
      ownerUserId: rule.ownerUserId,
      pairId: rule.pairId,
      message: _message(rule, condition, probe, probability),
      probabilityPercent: probability,
      basis: [
        InterpretationBasis(
          metric: condition.metric,
          description: probe.description,
          observedAt: probe.observedAt,
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
    RuleMetric? inputMetric,
    DateTime? inputObservedAt,
    String? evaluationFingerprint,
    List<String> staleInputMetrics = const [],
  }) {
    return RuleEvaluationResult(
      ruleId: rule.id,
      ruleVersion: rule.version,
      outcome: outcome,
      evaluatedAt: nowUtc.toUtc(),
      evaluationId:
          '${rule.id}:v${rule.version}:${evaluationFingerprint ?? '${outcome.name}:${note ?? ''}'}',
      inputObservationTimes: interpretation == null
          ? (inputMetric == null || inputObservedAt == null
                ? const {}
                : {inputMetric.name: inputObservedAt.toUtc()})
          : {
              for (final basis in interpretation.basis)
                if (basis.observedAt != null)
                  basis.metric.name: basis.observedAt!.toUtc(),
            },
      staleInputMetrics: List.unmodifiable(staleInputMetrics),
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
    this.observedAt,
    this.unavailableOutcome,
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

  final DateTime? observedAt;

  final RuleEvaluationOutcome? unavailableOutcome;

  /// Whether a stale observation should block the evaluation.
  ///
  /// True for snapshot metrics. False for metrics whose value already *is* an
  /// age or an availability classification (`locationAvailability`,
  /// `locationAge`, `offlineDuration`), which must stay evaluable or a rule such
  /// as "tell me when the location is stale" could never fire.
  final bool stalenessApplies;

  bool get hasValue => availability == DataAvailability.available;
}
