import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exposed from the misc library in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/presentation/providers/sync_providers.dart';
import 'package:kam/features/pairing/domain/models/pair_membership.dart';
import 'package:kam/features/pairing/presentation/providers/pairing_providers.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';
import 'package:kam/features/rules/data/repositories/in_memory_rule_repository.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/presentation/providers/rule_providers.dart';
import 'package:kam/features/rules/presentation/widgets/rule_interpretation_card.dart';

import '../support/rule_test_app.dart';
import '../support/test_app.dart';

void main() {
  /// The Long Charging rule from the phase's manual scenario.
  Rule longCharging({bool enabled = true}) => Rule(
    id: 'rule-long-charging',
    ownerUserId: testRuleScope.ownerUserId,
    pairId: testRuleScope.pairId,
    name: 'Long Charging',
    version: 1,
    condition: const RuleCondition(
      metric: RuleMetric.chargingDuration,
      operator: RuleOperator.greaterThanOrEqual,
      durationThreshold: Duration(minutes: 240),
    ),
    actions: const [
      RuleAction(
        type: RuleActionType.displayProbability,
        messageTemplate: 'Possible sleep period',
        probabilityPercent: 70,
      ),
    ],
    enabled: enabled,
    createdAt: testNow,
    updatedAt: testNow,
  );

  RemoteDeviceState chargingFor(Duration duration) => testPartnerState(
    observedAt: testNow,
    chargingState: 'charging',
    chargingDuration: duration,
    chargingStartedAt: testNow.subtract(duration),
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Iterable<Rule> seed,
    required RemoteDeviceState partnerState,
    String membershipStatus = 'active',
  }) async {
    useTallSurface(tester);
    await pumpTestApp(
      tester,
      overrides: <Override>[
        fixedClock(testNow),
        pairMembershipsProvider.overrideWith(
          (ref) => Stream.value([
            PairMembership(
              pairId: testRuleScope.pairId,
              memberIds: [testRuleScope.ownerUserId, testPartnerUserId],
              status: membershipStatus,
            ),
          ]),
        ),
        partnerScopeProvider.overrideWithValue(
          AsyncData<PartnerScope?>(
            PartnerScope(
              pairId: testRuleScope.pairId,
              partnerUserId: testPartnerUserId,
            ),
          ),
        ),
        partnerDisplayNameProvider.overrideWith((ref) => Stream.value('Nadia')),
        partnerSharingProvider.overrideWith(
          (ref) => Stream.value(
            const PairSharingState(
              paused: false,
              categories: {SharingCategory.battery, SharingCategory.charging},
            ),
          ),
        ),
        partnerDeviceStateProvider.overrideWith(
          (ref) => Stream.value(PartnerDeviceState(partnerState)),
        ),
        ruleRepositoryProvider.overrideWithValue(
          InMemoryRuleRepository(seed: seed),
        ),
        ruleScopeProvider.overrideWithValue(
          const AsyncData<RuleScope?>(testRuleScope),
        ),
      ],
    );
  }

  testWidgets('a matching rule is interpreted on the dashboard', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      seed: [longCharging()],
      partnerState: chargingFor(const Duration(minutes: 250)),
    );

    expect(find.text('What your rules say'), findsOneWidget);
    expect(find.byType(RuleInterpretationCard), findsOneWidget);
    expect(find.text('Long Charging'), findsWidgets);
    expect(find.text('Based on your rule'), findsOneWidget);
    expect(find.text('Possible sleep period'), findsOneWidget);
    expect(find.text('User-defined probability: 70%'), findsOneWidget);
    // The observed facts the interpretation came from are on screen too.
    expect(find.textContaining('Charging duration: 4h 10m'), findsOneWidget);
    expect(
      find.textContaining(
        'Rule condition: Charging duration is at least 4 hours',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the interpretation never states a verified behaviour', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      seed: [longCharging()],
      partnerState: chargingFor(const Duration(minutes: 250)),
    );

    for (final forbidden in const [
      'They are sleeping',
      'is sleeping',
      'are asleep',
      'powered off',
      'definitely',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('a disabled rule is stored but produces no interpretation', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      seed: [longCharging(enabled: false)],
      partnerState: chargingFor(const Duration(minutes: 250)),
    );

    expect(find.byType(RuleInterpretationCard), findsNothing);
    expect(find.text('No rule applies right now'), findsOneWidget);
    expect(find.text('Possible sleep period'), findsNothing);
  });

  testWidgets('a rule that does not match yet is not interpreted', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      seed: [longCharging()],
      partnerState: chargingFor(const Duration(minutes: 30)),
    );

    expect(find.byType(RuleInterpretationCard), findsNothing);
    expect(find.text('No rule applies right now'), findsOneWidget);
  });

  testWidgets('an ended pair stops partner-state interpretation', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      seed: [longCharging()],
      partnerState: chargingFor(const Duration(minutes: 250)),
      membershipStatus: 'revoked',
    );

    expect(find.text('What your rules say'), findsNothing);
    expect(find.byType(RuleInterpretationCard), findsNothing);
    expect(find.text('Possible sleep period'), findsNothing);
    expect(find.text('Connection unavailable'), findsOneWidget);
  });

  testWidgets('no rules for this member means nothing to interpret', (
    tester,
  ) async {
    // No rule scope at all: there is no rule set to evaluate for this member.
    useTallSurface(tester);
    await pumpTestApp(
      tester,
      overrides: <Override>[
        fixedClock(testNow),
        pairMembershipsProvider.overrideWith(
          (ref) => Stream.value([
            PairMembership(
              pairId: testRuleScope.pairId,
              memberIds: [testRuleScope.ownerUserId, testPartnerUserId],
              status: 'active',
            ),
          ]),
        ),
        partnerScopeProvider.overrideWithValue(
          AsyncData<PartnerScope?>(
            PartnerScope(
              pairId: testRuleScope.pairId,
              partnerUserId: testPartnerUserId,
            ),
          ),
        ),
        partnerDisplayNameProvider.overrideWith((ref) => Stream.value('Nadia')),
        partnerSharingProvider.overrideWith(
          (ref) => Stream.value(PairSharingState.none),
        ),
        partnerDeviceStateProvider.overrideWith(
          (ref) => Stream.value(
            PartnerDeviceState(chargingFor(const Duration(minutes: 250))),
          ),
        ),
        ruleScopeProvider.overrideWithValue(const AsyncData<RuleScope?>(null)),
      ],
    );

    expect(find.byType(RuleInterpretationCard), findsNothing);
    expect(find.text('Nothing to interpret yet'), findsOneWidget);
  });
}
