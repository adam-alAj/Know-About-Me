import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exposed from the misc library in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/app/providers.dart';
import 'package:kam/core/notifications/local_notification_service.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/core/time/clock.dart';
import 'package:kam/features/auth/domain/models/user_preferences.dart';
import 'package:kam/features/auth/presentation/providers/auth_providers.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/presentation/providers/sync_providers.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';
import 'package:kam/features/rules/data/repositories/in_memory_rule_repository.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/presentation/providers/rule_providers.dart';
import 'package:kam/features/rules/presentation/widgets/rule_interpretations_section.dart';

import '../fakes/fake_auth_repository.dart';
import '../support/rule_test_app.dart';
import '../support/test_app.dart';

/// Phase 20 §18: an old observation must never become a *new* alert.
///
/// Three things could otherwise replay an obsolete alert: the app restarting,
/// the connection returning, or Firestore's cache loading. None of them is a new
/// observation of the partner's state, so none of them may raise a notification.
void main() {
  /// A low-battery rule: `battery < 20`.
  ///
  /// The alert bookkeeping is process-wide (one live app session shares it), so
  /// each test that expects an alert uses its own rule id.
  Rule lowBatteryRule({String id = 'rule-battery-low'}) => testRule(
    id: id,
    name: 'Battery low',
    condition: const RuleCondition(
      metric: RuleMetric.batteryPercentage,
      operator: RuleOperator.lessThan,
      numericThreshold: 20,
    ),
    actions: const [
      RuleAction(
        type: RuleActionType.displayStatus,
        messageTemplate: 'Battery is running low',
      ),
    ],
  );

  Future<StreamController<PartnerDeviceState?>> pumpSection(
    WidgetTester tester, {
    required _RecordingNotificationService notifications,
    required Iterable<Rule> seed,
  }) async {
    final states = StreamController<PartnerDeviceState?>();
    addTearDown(states.close);
    // A benign first reading, so the section is evaluating rather than showing
    // its loading spinner: a spinner keeps scheduling frames and would make
    // `pumpAndSettle` meaningless.
    states.add(PartnerDeviceState(testPartnerState(batteryPercentage: 80)));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          clockProvider.overrideWithValue(FixedClock(testNow)),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(initialIdentity: testIdentity),
          ),
          currentUserPreferencesProvider.overrideWithValue(
            const AsyncData<Result<UserPreferences>>(
              Success<UserPreferences>(UserPreferences.defaults),
            ),
          ),
          localNotificationServiceProvider.overrideWithValue(notifications),
          ruleRepositoryProvider.overrideWithValue(
            InMemoryRuleRepository(seed: seed),
          ),
          ruleScopeProvider.overrideWithValue(
            const AsyncData<RuleScope?>(testRuleScope),
          ),
          partnerSharingProvider.overrideWith(
            (ref) => Stream.value(
              const PairSharingState(
                paused: false,
                categories: {SharingCategory.battery},
              ),
            ),
          ),
          partnerDeviceStateProvider.overrideWith((ref) => states.stream),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RuleInterpretationsSection(now: testNow),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return states;
  }

  testWidgets('a stale cached reading never raises a notification', (
    tester,
  ) async {
    final notifications = _RecordingNotificationService();
    final states = await pumpSection(
      tester,
      notifications: notifications,
      seed: [lowBatteryRule()],
    );

    // Battery is genuinely below the threshold — but it was observed four hours
    // ago. That is not a current fact, so it is not an alert
    // (Phase 20 §17, §18).
    states.add(
      PartnerDeviceState(
        testPartnerState(
          observedAt: testNow.subtract(const Duration(hours: 4)),
          batteryPercentage: 18,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(notifications.shown, isEmpty);
    expect(find.textContaining('no longer current'), findsWidgets);
  });

  testWidgets('a fresh reading raises exactly one notification', (
    tester,
  ) async {
    final notifications = _RecordingNotificationService();
    final states = await pumpSection(
      tester,
      notifications: notifications,
      seed: [lowBatteryRule()],
    );

    final fresh = PartnerDeviceState(testPartnerState(batteryPercentage: 18));
    states.add(fresh);
    await tester.pumpAndSettle();

    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single.title, 'Rule alert');
  });

  testWidgets('a reconnect re-delivering the same state does not alert again', (
    tester,
  ) async {
    final notifications = _RecordingNotificationService();
    final states = await pumpSection(
      tester,
      notifications: notifications,
      seed: [lowBatteryRule(id: 'rule-battery-reconnect')],
    );

    final fresh = PartnerDeviceState(testPartnerState(batteryPercentage: 18));
    states.add(fresh);
    await tester.pumpAndSettle();
    expect(notifications.shown, hasLength(1));

    // The connection drops and returns, so Firestore re-delivers the same
    // authorized snapshot. It is not a new observation, so it must not be a new
    // alert (Phase 20 §18, §27).
    states.add(fresh);
    await tester.pumpAndSettle();
    expect(notifications.shown, hasLength(1));
  });
}

/// A local-notification sink that records what this device would have shown.
class _RecordingNotificationService implements LocalNotificationService {
  final List<LocalNotificationRequest> shown = <LocalNotificationRequest>[];

  @override
  bool get isSupported => true;

  @override
  Future<Result<NotificationPermissionState>> permissionState() async =>
      const Success(NotificationPermissionState.granted);

  @override
  Future<Result<NotificationPermissionState>> requestPermission() async =>
      const Success(NotificationPermissionState.granted);

  @override
  Future<Result<void>> show(LocalNotificationRequest request) async {
    shown.add(request);
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> cancelAll() async => const Success<void>(null);
}
