import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/features/device_state/domain/models/device_state.dart';
import 'package:kam/features/device_state/domain/models/metric_value.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/models/device_location_state.dart'
    as normalized_location;
import 'package:kam/features/device_state/domain/models/battery_state.dart'
    as normalized_battery;
import 'package:kam/features/device_state/domain/models/network_state.dart'
    as normalized_network;
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_evaluation.dart';
import 'package:kam/features/rules/domain/rule_evaluator.dart';
import 'package:kam/features/location/domain/models/location_state.dart';

/// Unit tests for the client-side rule engine.
///
/// This is the Spark-only replacement for server-side rule evaluation
/// (ADR-009), so its behaviour is specified here rather than assumed. The
/// evaluator is pure and clock-injected, so every case is deterministic.
void main() {
  final now = DateTime.utc(2026, 9, 26, 12);

  MetricValue<T> observed<T>(T value, {Duration age = Duration.zero}) =>
      MetricValue<T>.observed(
        value: value,
        observedAt: now.subtract(age),
        source: 'test',
      );

  DeviceState state({
    MetricValue<int>? battery,
    MetricValue<ChargingState>? charging,
    MetricValue<Duration>? chargingDuration,
    MetricValue<NetworkStatus>? network,
    MetricValue<Duration>? offlineDuration,
  }) {
    return DeviceState(
      deviceId: 'devA',
      batteryPercentage: battery ?? const MetricValue<int>.unknown(),
      chargingState: charging ?? const MetricValue<ChargingState>.unknown(),
      chargingDuration:
          chargingDuration ?? const MetricValue<Duration>.unknown(),
      networkStatus: network ?? const MetricValue<NetworkStatus>.unknown(),
      availability: const MetricValue<DeviceAvailabilityState>.unknown(),
      offlineDuration: offlineDuration ?? const MetricValue<Duration>.unknown(),
      lastActivity: const MetricValue<Duration>.unknown(),
      generatedAt: now,
    );
  }

  Rule rule({
    required RuleCondition condition,
    List<RuleAction>? actions,
    int version = 1,
    RuleConditionGroup? conditionGroup,
    bool enabled = true,
    Duration cooldown = const Duration(minutes: 30),
    DateTime? lastTriggeredAt,
  }) {
    return Rule(
      id: 'r1',
      ownerUserId: 'uA',
      pairId: 'p1',
      name: 'Possible sleep',
      condition: condition,
      conditionGroup: conditionGroup,
      version: version,
      actions:
          actions ??
          const [
            RuleAction(
              type: RuleActionType.displayProbability,
              messageTemplate: '{partnerName} is sleeping now',
              probabilityPercent: 70,
            ),
          ],
      enabled: enabled,
      cooldown: cooldown,
      lastTriggeredAt: lastTriggeredAt,
    );
  }

  const batteryAtLeast50 = RuleCondition(
    metric: RuleMetric.batteryPercentage,
    operator: RuleOperator.greaterThanOrEqual,
    numericThreshold: 50,
  );

  const evaluator = RuleEvaluator(partnerName: 'Afraa');

  group('numeric threshold conditions', () {
    test('a satisfied threshold matches and produces an interpretation', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
      expect(result.shouldNotify, isTrue);
      expect(result.interpretation, isNotNull);
      expect(result.interpretation!.basis, hasLength(1));
      expect(result.interpretation!.basis.first.description, 'Battery: 82%');
    });

    test('an unsatisfied threshold does not match and produces nothing', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(battery: observed(12)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.notMatched);
      expect(result.interpretation, isNull);
      expect(result.shouldNotify, isFalse);
    });

    test('the boundary value matches, as the operator states', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(battery: observed(50)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
    });

    test(
      'strict and inclusive comparisons treat the exact boundary correctly',
      () {
        const cases = <(RuleOperator, int, RuleEvaluationOutcome)>[
          (RuleOperator.greaterThan, 50, RuleEvaluationOutcome.notMatched),
          (RuleOperator.greaterThanOrEqual, 50, RuleEvaluationOutcome.matched),
          (RuleOperator.lessThan, 50, RuleEvaluationOutcome.notMatched),
          (RuleOperator.lessThanOrEqual, 50, RuleEvaluationOutcome.matched),
          (RuleOperator.equalTo, 50, RuleEvaluationOutcome.matched),
          (RuleOperator.notEqualTo, 50, RuleEvaluationOutcome.notMatched),
        ];
        for (final (operator, value, expected) in cases) {
          final result = evaluator.evaluate(
            rule: rule(
              condition: RuleCondition(
                metric: RuleMetric.batteryPercentage,
                operator: operator,
                numericThreshold: 50,
              ),
            ),
            deviceState: state(battery: observed(value)),
            nowUtc: now,
          );
          expect(result.outcome, expected, reason: operator.name);
        }
      },
    );
  });

  group('duration conditions', () {
    const chargingFor4h = RuleCondition(
      metric: RuleMetric.chargingDuration,
      operator: RuleOperator.greaterThanOrEqual,
      numericThreshold: 240,
    );

    test('a numeric threshold on a duration metric is read as minutes', () {
      final result = evaluator.evaluate(
        rule: rule(condition: chargingFor4h),
        deviceState: state(
          chargingDuration: MetricValue<Duration>.derived(
            value: const Duration(hours: 4, minutes: 20),
            observedAt: now,
            source: 'test',
          ),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
      expect(
        result.interpretation!.basis.first.description,
        contains('4h 20m'),
      );
    });

    test('a duration below the threshold does not match', () {
      final result = evaluator.evaluate(
        rule: rule(condition: chargingFor4h),
        deviceState: state(
          chargingDuration: MetricValue<Duration>.derived(
            value: const Duration(hours: 1),
            observedAt: now,
            source: 'test',
          ),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.notMatched);
    });

    test('240 minute threshold treats 239, 240, and 241 deterministically', () {
      const values = <(int, RuleEvaluationOutcome)>[
        (239, RuleEvaluationOutcome.notMatched),
        (240, RuleEvaluationOutcome.matched),
        (241, RuleEvaluationOutcome.matched),
      ];
      for (final (minutes, expected) in values) {
        final result = evaluator.evaluate(
          rule: rule(condition: chargingFor4h),
          deviceState: state(
            chargingDuration: MetricValue<Duration>.derived(
              value: Duration(minutes: minutes),
              observedAt: now,
              source: 'test',
            ),
          ),
          nowUtc: now,
        );
        expect(result.outcome, expected, reason: '$minutes minutes');
      }
    });

    test('hasRemainedInStateFor requires the state and its duration', () {
      const condition = RuleCondition(
        metric: RuleMetric.chargingState,
        operator: RuleOperator.hasRemainedInStateFor,
        stateValue: 'charging',
        durationThreshold: Duration(hours: 4),
      );

      final satisfied = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(
          charging: observed(ChargingState.charging),
          chargingDuration: MetricValue<Duration>.derived(
            value: const Duration(hours: 4, minutes: 5),
            observedAt: now,
            source: 'test',
          ),
        ),
        nowUtc: now,
      );
      expect(satisfied.outcome, RuleEvaluationOutcome.matched);

      // Right state, not long enough.
      final tooShort = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(
          charging: observed(ChargingState.charging),
          chargingDuration: MetricValue<Duration>.derived(
            value: const Duration(hours: 2),
            observedAt: now,
            source: 'test',
          ),
        ),
        nowUtc: now,
      );
      expect(tooShort.outcome, RuleEvaluationOutcome.notMatched);

      // Long enough, wrong state.
      final wrongState = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(
          charging: observed(ChargingState.notCharging),
          chargingDuration: MetricValue<Duration>.derived(
            value: const Duration(hours: 6),
            observedAt: now,
            source: 'test',
          ),
        ),
        nowUtc: now,
      );
      expect(wrongState.outcome, RuleEvaluationOutcome.notMatched);
    });
  });

  group('state conditions', () {
    test('isA compares against the observed state name', () {
      const condition = RuleCondition(
        metric: RuleMetric.chargingState,
        operator: RuleOperator.isA,
        stateValue: 'charging',
      );

      final result = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(charging: observed(ChargingState.charging)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
    });

    test('an unknown state is insufficient data, not a non-match', () {
      const condition = RuleCondition(
        metric: RuleMetric.chargingState,
        operator: RuleOperator.isA,
        stateValue: 'charging',
      );

      final result = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.unknown);
      expect(result.isIndeterminate, isTrue);
      expect(result.interpretation, isNull);
    });

    test('an unsupported metric has its own structured outcome', () {
      const condition = RuleCondition(
        metric: RuleMetric.batteryPercentage,
        operator: RuleOperator.greaterThan,
        numericThreshold: 50,
      );

      final result = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(
          battery: const MetricValue<int>.unsupported(source: 'test'),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.unsupported);
      expect(result.note, contains('unsupported'));
    });

    test('a withheld metric is reported as insufficient data', () {
      const condition = RuleCondition(
        metric: RuleMetric.batteryPercentage,
        operator: RuleOperator.greaterThan,
        numericThreshold: 50,
      );

      final result = evaluator.evaluate(
        rule: rule(condition: condition),
        deviceState: state(
          battery: const MetricValue<int>.paused(source: 'test'),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.insufficientData);
    });
  });

  group('staleness', () {
    test('a stale value does not silently drive a match (NFR-025)', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(
          battery: observed(82, age: const Duration(minutes: 30)),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.staleData);
      expect(result.isIndeterminate, isTrue);
      expect(result.interpretation, isNull);
    });

    test('stale data may be opted into, but stays flagged as stale', () {
      const permissive = RuleEvaluator(allowStaleData: true);

      final result = permissive.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(
          battery: observed(82, age: const Duration(minutes: 30)),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
      expect(result.interpretation!.basis.first.description, 'Battery: 82%');
      expect(result.staleInputMetrics, ['batteryPercentage']);
    });

    test('a recently observed value is still usable', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(
          battery: observed(82, age: const Duration(minutes: 5)),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
    });

    test('freshness thresholds come from the metric policy', () {
      expect(
        FreshnessPolicy.standard.classifyAge(const Duration(seconds: 30)),
        DataFreshness.fresh,
      );
      expect(
        FreshnessPolicy.standard.classifyAge(const Duration(minutes: 30)),
        DataFreshness.stale,
      );
    });
  });

  group('disabled rules and cooldown', () {
    test('a disabled rule is never evaluated (FR-034)', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50, enabled: false),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.disabled);
      expect(result.interpretation, isNull);
    });

    test('a match inside the cooldown keeps the interpretation but does not '
        'notify again (FR-039)', () {
      final result = evaluator.evaluate(
        rule: rule(
          condition: batteryAtLeast50,
          cooldown: const Duration(minutes: 30),
          lastTriggeredAt: now.subtract(const Duration(minutes: 5)),
        ),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.coolingDown);
      expect(result.interpretation, isNotNull);
      expect(result.shouldNotify, isFalse);
      expect(result.isMatched, isTrue);
    });

    test('a match after the cooldown notifies', () {
      final result = evaluator.evaluate(
        rule: rule(
          condition: batteryAtLeast50,
          cooldown: const Duration(minutes: 30),
          lastTriggeredAt: now.subtract(const Duration(hours: 2)),
        ),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
      expect(result.shouldNotify, isTrue);
    });
  });

  group('interpretations are never facts', () {
    test('a configured percentage is presented as a possibility', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      final interpretation = result.interpretation!;
      expect(interpretation.message, startsWith('There is a 70% possibility'));
      expect(interpretation.probabilityPercent, 70);
      expect(interpretation.hasUserDefinedProbability, isTrue);
      // The type-level guarantee that an interpretation is not a measurement.
      expect(interpretation.isObjectiveFact, isFalse);
      expect(interpretation.sourceCondition, batteryAtLeast50);
    });

    test('the partner name is substituted into the template (FR-031)', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(result.interpretation!.message, contains('Afraa'));
      expect(result.interpretation!.message, isNot(contains('{partnerName}')));
    });

    test(
      'a rule without a probability produces a plain user-defined message',
      () {
        final result = evaluator.evaluate(
          rule: rule(
            condition: batteryAtLeast50,
            actions: const [
              RuleAction(
                type: RuleActionType.displayMessage,
                messageTemplate: 'Afraa\'s phone is charging late',
              ),
            ],
          ),
          deviceState: state(battery: observed(82)),
          nowUtc: now,
        );

        expect(
          result.interpretation!.message,
          'Afraa\'s phone is charging late',
        );
        expect(result.interpretation!.probabilityPercent, isNull);
      },
    );

    test('a match without any action falls back to a named interpretation', () {
      final result = evaluator.evaluate(
        rule: rule(condition: batteryAtLeast50, actions: const []),
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(result.interpretation!.message, contains('Possible sleep'));
    });
  });

  group('location-derived metrics', () {
    LocationState location(MetricValue<Coordinate> coordinates) =>
        LocationState(
          coordinates: coordinates,
          distanceFromHomeKm: const MetricValue<double>.unknown(),
          presence: HomePresence.unknown,
        );

    test('distance follows the location category and reports a value', () {
      final result = evaluator.evaluate(
        rule: rule(
          condition: const RuleCondition(
            metric: RuleMetric.distanceFromHomeKm,
            operator: RuleOperator.greaterThan,
            numericThreshold: 5,
          ),
        ),
        deviceState: state(),
        locationState: LocationState(
          coordinates: MetricValue<Coordinate>.observed(
            value: const Coordinate(latitude: 52.5, longitude: 13.4),
            observedAt: now,
            source: 'test',
          ),
          distanceFromHomeKm: MetricValue<double>.derived(
            value: 12.5,
            observedAt: now,
            source: 'test',
          ),
          presence: HomePresence.awayFromHome,
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
    });

    test('a missing location state is unknown, never zero', () {
      final result = evaluator.evaluate(
        rule: rule(
          condition: const RuleCondition(
            metric: RuleMetric.distanceFromHomeKm,
            operator: RuleOperator.greaterThan,
            numericThreshold: 5,
          ),
        ),
        deviceState: state(),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.unknown);
    });

    test('location availability is reported as a named state', () {
      final result = evaluator.evaluate(
        rule: rule(
          condition: const RuleCondition(
            metric: RuleMetric.locationAvailability,
            operator: RuleOperator.isA,
            stateValue: 'stale',
          ),
        ),
        deviceState: state(),
        locationState: location(
          MetricValue<Coordinate>.observed(
            value: const Coordinate(latitude: 52.5, longitude: 13.4),
            observedAt: now.subtract(const Duration(days: 1)),
            source: 'test',
            freshnessPolicy: FreshnessPolicy.slow,
          ),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
    });

    test('an unavailable location reports unsupported rather than a value', () {
      final result = evaluator.evaluate(
        rule: rule(
          condition: const RuleCondition(
            metric: RuleMetric.locationAvailability,
            operator: RuleOperator.isA,
            stateValue: 'available',
          ),
        ),
        deviceState: state(),
        locationState: location(
          const MetricValue<Coordinate>.unsupported(source: 'test'),
        ),
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.unsupported);
    });
  });

  group('evaluating many rules', () {
    const batteryBelow5 = RuleCondition(
      metric: RuleMetric.batteryPercentage,
      operator: RuleOperator.lessThan,
      numericThreshold: 5,
    );

    test('one result is returned per rule, in order, independently', () {
      final results = evaluator.evaluateAll(
        rules: [
          rule(condition: batteryAtLeast50),
          rule(condition: batteryBelow5),
          rule(condition: batteryAtLeast50, enabled: false),
        ],
        deviceState: state(battery: observed(82)),
        nowUtc: now,
      );

      expect(results, hasLength(3));
      expect(results[0].outcome, RuleEvaluationOutcome.matched);
      expect(results[1].outcome, RuleEvaluationOutcome.notMatched);
      expect(results[2].outcome, RuleEvaluationOutcome.disabled);
    });

    test('each rule is evaluated on its own merits', () {
      final results = evaluator.evaluateAll(
        rules: [
          rule(condition: batteryAtLeast50),
          rule(condition: batteryBelow5),
        ],
        deviceState: state(
          battery: observed(82, age: const Duration(hours: 2)),
        ),
        nowUtc: now,
      );

      // Both are indeterminate for the same reason, independently reported.
      expect(results[0].outcome, RuleEvaluationOutcome.staleData);
      expect(results[1].outcome, RuleEvaluationOutcome.staleData);
    });
  });

  group('condition groups and stable evaluation metadata', () {
    const batteryAbove50 = RuleCondition(
      metric: RuleMetric.batteryPercentage,
      operator: RuleOperator.greaterThan,
      numericThreshold: 50,
    );
    const charging = RuleCondition(
      metric: RuleMetric.chargingState,
      operator: RuleOperator.isA,
      stateValue: 'charging',
    );

    test('AND and OR groups preserve three-valued unknown semantics', () {
      final andResult = evaluator.evaluate(
        rule: rule(
          condition: batteryAbove50,
          conditionGroup: const RuleConditionGroup(
            operator: RuleGroupOperator.all,
            conditions: [batteryAbove50, charging],
          ),
        ),
        deviceState: state(battery: observed(70)),
        nowUtc: now,
      );
      expect(andResult.outcome, RuleEvaluationOutcome.unknown);
      expect(andResult.matchedConditions, [0]);
      expect(andResult.unknownConditions, [1]);

      final orResult = evaluator.evaluate(
        rule: rule(
          condition: batteryAbove50,
          conditionGroup: const RuleConditionGroup(
            operator: RuleGroupOperator.any,
            conditions: [batteryAbove50, charging],
          ),
        ),
        deviceState: state(battery: observed(70)),
        nowUtc: now,
      );
      expect(orResult.outcome, RuleEvaluationOutcome.matched);
      expect(orResult.matchedConditions, [0]);
      expect(orResult.ruleVersion, 1);
      expect(orResult.evaluationId, isNotEmpty);
    });

    test(
      'rule version and evaluation fingerprint are stable for same input',
      () {
        final input = state(battery: observed(82));
        final configured = rule(condition: batteryAtLeast50, version: 7);
        final first = evaluator.evaluate(
          rule: configured,
          deviceState: input,
          nowUtc: now,
        );
        final second = evaluator.evaluate(
          rule: configured,
          deviceState: input,
          nowUtc: now.add(const Duration(minutes: 1)),
        );

        expect(first.ruleVersion, 7);
        expect(first.evaluationId, second.evaluationId);
        expect(first.interpretation!.id, second.interpretation!.id);
        expect(first.inputObservationTimes['batteryPercentage'], now);
      },
    );

    test(
      'malformed metric/operator combinations return a structured error',
      () {
        final result = evaluator.evaluate(
          rule: rule(
            condition: const RuleCondition(
              metric: RuleMetric.batteryPercentage,
              operator: RuleOperator.isA,
              stateValue: 'charging',
            ),
          ),
          deviceState: state(battery: observed(82)),
          nowUtc: now,
        );
        expect(result.outcome, RuleEvaluationOutcome.error);
        expect(result.note, contains('invalid_numeric_value'));
        expect(result.interpretation, isNull);
      },
    );
  });

  group('canonical Phase 6–12 snapshot input', () {
    test('evaluates normalized battery facts without using platform APIs', () {
      final snapshot = DeviceStateSnapshot(
        deviceId: 'device-a',
        collectedAt: now,
        capabilities: const {},
        battery: normalized_battery.BatteryState(
          percentage: StateObservation<int>(
            availability: CapabilityAvailability.available,
            value: 82,
            observedAt: now,
            source: 'test',
          ),
          chargingState:
              const StateObservation<normalized_battery.BatteryChargingState>(
                availability: CapabilityAvailability.unknown,
              ),
          chargingDuration: const StateObservation<Duration>(
            availability: CapabilityAvailability.unknown,
          ),
          chargingSource:
              const StateObservation<normalized_battery.BatteryChargingSource>(
                availability: CapabilityAvailability.unknown,
              ),
        ),
      );
      final result = evaluator.evaluateSnapshot(
        rule: rule(condition: batteryAtLeast50, version: 4),
        snapshot: snapshot,
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.matched);
      expect(result.ruleVersion, 4);
      expect(result.inputObservationTimes['batteryPercentage'], now);
      expect(result.interpretation!.basis.single.description, 'Battery: 82%');
    });

    test('preserves an unsupported normalized network capability', () {
      final snapshot = DeviceStateSnapshot(
        deviceId: 'device-a',
        collectedAt: now,
        capabilities: const {},
        network: normalized_network.NetworkState(
          connectivity:
              const StateObservation<normalized_network.ConnectivityType>(
                availability: CapabilityAvailability.unsupported,
              ),
          internet:
              const StateObservation<normalized_network.InternetReachability>(
                availability: CapabilityAvailability.unknown,
              ),
          status:
              const StateObservation<normalized_network.NetworkOnlineStatus>(
                availability: CapabilityAvailability.unknown,
              ),
          offlineDuration: const StateObservation<Duration>(
            availability: CapabilityAvailability.unknown,
          ),
        ),
      );
      final result = evaluator.evaluateSnapshot(
        rule: rule(
          condition: const RuleCondition(
            metric: RuleMetric.networkType,
            operator: RuleOperator.isA,
            stateValue: 'wifi',
          ),
        ),
        snapshot: snapshot,
        nowUtc: now,
      );

      expect(result.outcome, RuleEvaluationOutcome.unsupported);
      expect(result.interpretation, isNull);
    });

    test(
      'evaluates offline state and duration from one normalized snapshot',
      () {
        final snapshot = DeviceStateSnapshot(
          deviceId: 'device-a',
          collectedAt: now,
          capabilities: const {},
          network: normalized_network.NetworkState(
            connectivity:
                const StateObservation<normalized_network.ConnectivityType>(
                  availability: CapabilityAvailability.available,
                  value: normalized_network.ConnectivityType.none,
                ),
            internet:
                const StateObservation<normalized_network.InternetReachability>(
                  availability: CapabilityAvailability.available,
                  value: normalized_network.InternetReachability.unavailable,
                ),
            status: StateObservation<normalized_network.NetworkOnlineStatus>(
              availability: CapabilityAvailability.available,
              value: normalized_network.NetworkOnlineStatus.offline,
              observedAt: now,
            ),
            offlineDuration: StateObservation<Duration>(
              availability: CapabilityAvailability.available,
              value: const Duration(minutes: 90),
              observedAt: now,
            ),
          ),
        );
        final offline = const RuleCondition(
          metric: RuleMetric.networkStatus,
          operator: RuleOperator.isA,
          stateValue: 'offline',
        );
        final offlineLongEnough = const RuleCondition(
          metric: RuleMetric.offlineDuration,
          operator: RuleOperator.greaterThanOrEqual,
          numericThreshold: 60,
        );
        final result = evaluator.evaluateSnapshot(
          rule: rule(
            condition: offline,
            conditionGroup: RuleConditionGroup(
              operator: RuleGroupOperator.all,
              conditions: [offline, offlineLongEnough],
            ),
          ),
          snapshot: snapshot,
          nowUtc: now,
        );

        expect(result.outcome, RuleEvaluationOutcome.matched);
        expect(result.matchedConditions, [0, 1]);
        expect(result.interpretation!.basis, hasLength(2));
      },
    );

    test(
      'normalizes distance from metres to kilometres and rejects stale fixes',
      () {
        DeviceStateSnapshot snapshotFor(StateObservation<double> distance) =>
            DeviceStateSnapshot(
              deviceId: 'device-a',
              collectedAt: now,
              capabilities: const {},
              location: normalized_location.DeviceLocationState(
                location:
                    const StateObservation<normalized_location.LocationFix>(
                      availability: CapabilityAvailability.unknown,
                    ),
                lastKnownLocation:
                    const StateObservation<normalized_location.LocationFix>(
                      availability: CapabilityAvailability.unknown,
                    ),
                permission: const StateObservation<DevicePermissionState>(
                  availability: CapabilityAvailability.unknown,
                ),
                serviceState: normalized_location.LocationServiceState.unknown,
                distanceFromHome: distance,
                presence: HomePresence.awayFromHome,
                homeConfigured: true,
                homeEnabled: true,
              ),
            );
        const condition = RuleCondition(
          metric: RuleMetric.distanceFromHomeKm,
          operator: RuleOperator.greaterThan,
          numericThreshold: 5,
        );
        final current = evaluator.evaluateSnapshot(
          rule: rule(condition: condition),
          snapshot: snapshotFor(
            StateObservation<double>(
              availability: CapabilityAvailability.available,
              value: 5100,
              observedAt: now,
            ),
          ),
          nowUtc: now,
        );
        final stale = evaluator.evaluateSnapshot(
          rule: rule(condition: condition),
          snapshot: snapshotFor(
            StateObservation<double>(
              availability: CapabilityAvailability.stale,
              value: 5100,
              observedAt: now.subtract(const Duration(hours: 6)),
            ),
          ),
          nowUtc: now,
        );

        expect(current.outcome, RuleEvaluationOutcome.matched);
        expect(
          current.interpretation!.basis.single.description,
          'Distance from home: 5.1 km',
        );
        expect(stale.outcome, RuleEvaluationOutcome.staleData);
      },
    );
  });
}
