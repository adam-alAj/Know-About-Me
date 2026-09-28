import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exposed from the misc library in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/state_observation.dart';
import 'package:kam/features/location/domain/models/location_state.dart';
import 'package:kam/features/rules/data/repositories/in_memory_rule_repository.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/presentation/providers/rule_providers.dart';

import 'test_app.dart';

/// The owner/pair scope every rule widget test uses.
const RuleScope testRuleScope = RuleScope(
  ownerUserId: 'user-a',
  pairId: 'pair-1',
);

/// The instant every Phase 15 evaluation test starts from.
///
/// Matches the `createdAt` [testRule] uses, so a rule and the state it is
/// evaluated against share one clock (NFR-033).
final DateTime testNow = DateTime.utc(2026, 9, 28, 12);

/// An authorized partner state document shaped exactly like
/// `RemoteDeviceStateParser` produces one.
///
/// Only the metrics a test names are published; everything else stays absent,
/// which is what surfaces as `unavailable` and is what the adapter must never
/// fill in with a plausible default.
RemoteDeviceState testPartnerState({
  DateTime? now,
  DateTime? observedAt,
  int? batteryPercentage,
  String? chargingState,
  Duration? chargingDuration,
  DateTime? chargingStartedAt,
  String? networkStatus,
  DateTime? lastOnlineAt,
  String? screenState,
  String? activityState,
  DateTime? lastActivityAt,
  String? availabilityState,
  double? distanceFromHomeKm,
  HomePresence? presence,
  double? latitude,
  double? longitude,
  DateTime? locationObservedAt,
}) {
  final at = now ?? testNow;
  final observed = observedAt ?? at;
  final observations = <DeviceMetric, StateObservation<Object?>>{};

  void publish(
    DeviceMetric metric,
    Object? value, {
    DateTime? when,
  }) {
    observations[metric] = StateObservation<Object?>(
      availability: CapabilityAvailability.available,
      value: value,
      observedAt: when ?? observed,
      source: 'partner_sync',
    );
  }

  if (batteryPercentage != null) {
    publish(DeviceMetric.batteryPercentage, batteryPercentage);
  }
  if (chargingState != null) {
    publish(DeviceMetric.chargingState, chargingState);
  }
  if (chargingDuration != null) {
    // The wire format stamps this with the session start, exactly as
    // `RemoteDeviceStateParser` does, so the adapter's own handling is exercised
    // rather than assumed.
    publish(
      DeviceMetric.chargingDuration,
      chargingDuration,
      when: chargingStartedAt ?? observed,
    );
  }
  if (networkStatus != null) {
    publish(
      DeviceMetric.networkStatus,
      networkStatus,
      when: lastOnlineAt ?? observed,
    );
  }
  if (screenState != null) publish(DeviceMetric.screenState, screenState);
  if (activityState != null) publish(DeviceMetric.activityState, activityState);
  if (availabilityState != null) {
    publish(DeviceMetric.deviceAvailability, availabilityState);
  }
  if (lastActivityAt != null) {
    publish(DeviceMetric.lastActivity, lastActivityAt, when: lastActivityAt);
  }

  return RemoteDeviceState(
    pairId: testRuleScope.pairId,
    ownerUserId: testPartnerUserId,
    observations: Map<DeviceMetric, StateObservation<Object?>>.unmodifiable(
      observations,
    ),
    schemaVersion: 1,
    stateVersion: 1,
    observedAt: observed,
    lastOnlineAt: lastOnlineAt,
    lastActivityAt: lastActivityAt,
    chargingStartedAt: chargingStartedAt,
    receivedAt: observed,
    isFromCache: false,
    location: latitude == null || longitude == null
        ? null
        : RemoteLocationState(
            availability: CapabilityAvailability.available,
            latitude: latitude,
            longitude: longitude,
            approximate: false,
            distanceFromHomeKm: distanceFromHomeKm,
            presence: presence,
            observedAt: locationObservedAt ?? observed,
          ),
  );
}

/// The partner user id [testRuleScope] belongs to.
const String testPartnerUserId = 'user-b';

/// A stored rule owned by [testRuleScope].
Rule testRule({
  String id = 'rule-1',
  String name = 'Long Charging',
  bool enabled = true,
  RuleCondition? condition,
  List<RuleAction>? actions,
  DateTime? updatedAt,
}) {
  final now = DateTime.utc(2026, 9, 28, 12);
  return Rule(
    id: id,
    ownerUserId: 'user-a',
    pairId: 'pair-1',
    name: name,
    condition:
        condition ??
        const RuleCondition(
          metric: RuleMetric.chargingDuration,
          operator: RuleOperator.greaterThanOrEqual,
          durationThreshold: Duration(hours: 4),
        ),
    actions:
        actions ??
        const [
          RuleAction(
            type: RuleActionType.displayStatus,
            messageTemplate: 'Away from home',
          ),
        ],
    enabled: enabled,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

/// Pumps the real app with rule providers overridden, then (by default) opens
/// the Rules destination the way a user does.
///
/// The real router and authentication guard stay in place, so navigation is
/// exercised rather than assumed. Returns the in-memory repository so a test can
/// assert on what was actually written.
Future<InMemoryRuleRepository> pumpAppAtRules(
  WidgetTester tester, {
  Iterable<Rule> seed = const <Rule>[],
  bool navigate = true,
  bool hasScope = true,
}) async {
  final repository = InMemoryRuleRepository(seed: seed);
  await pumpTestApp(
    tester,
    overrides: <Override>[
      ruleRepositoryProvider.overrideWithValue(repository),
      if (hasScope)
        ruleScopeProvider.overrideWithValue(
          const AsyncData<RuleScope?>(testRuleScope),
        ),
    ],
  );
  if (navigate) {
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
  }
  return repository;
}

/// Opens the rule builder from the rules screen.
Future<void> openRuleBuilder(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

/// Gives the test a tall surface so the whole builder form is laid out and can
/// be interacted with, instead of a lazily-built list leaving fields unbuilt.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Selects [option] from the dropdown of type [T].
Future<void> chooseDropdownOption<T>(
  WidgetTester tester,
  String option,
) async {
  await tester.tap(find.byType(DropdownButton<T>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}
