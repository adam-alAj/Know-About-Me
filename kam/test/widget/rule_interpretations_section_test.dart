import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exposed from the misc library in Riverpod 3.x.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/app/providers.dart';
import 'package:kam/core/time/clock.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/presentation/providers/sync_providers.dart';
import 'package:kam/features/rules/data/repositories/in_memory_rule_repository.dart';
import 'package:kam/features/rules/domain/models/rule.dart';
import 'package:kam/features/rules/domain/rule_draft.dart';
import 'package:kam/features/rules/presentation/providers/rule_providers.dart';
import 'package:kam/features/rules/presentation/widgets/rule_interpretation_card.dart';
import 'package:kam/features/rules/presentation/widgets/rule_interpretations_section.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';

import '../support/rule_test_app.dart';

/// A controller that never finishes loading, so the loading state is real
/// rather than simulated.
class _PendingRulesController extends RulesController {
  @override
  Future<List<Rule>> build() => Completer<List<Rule>>().future;
}

/// A controller whose read fails.
class _FailingRulesController extends RulesController {
  @override
  Future<List<Rule>> build() async => throw StateError('rules unavailable');
}

void main() {
  Rule chargingRule({
    String id = 'rule-1',
    String name = 'Long Charging',
    bool enabled = true,
    RuleOutputKind output = RuleOutputKind.probability,
    String outputText = 'Possible sleep period',
    int? probability = 70,
  }) => Rule(
    id: id,
    ownerUserId: testRuleScope.ownerUserId,
    pairId: testRuleScope.pairId,
    name: name,
    condition: const RuleCondition(
      metric: RuleMetric.chargingDuration,
      operator: RuleOperator.greaterThanOrEqual,
      durationThreshold: Duration(hours: 4),
    ),
    actions: [
      RuleAction(
        type: output.actionType,
        messageTemplate: outputText,
        probabilityPercent: output == RuleOutputKind.probability
            ? probability
            : null,
      ),
    ],
    enabled: enabled,
    createdAt: testNow,
    updatedAt: testNow,
  );

  Future<void> pumpSection(
    WidgetTester tester, {
    required Iterable<Rule> seed,
    Object? partnerState = _unset,
    List<Override> overrides = const <Override>[],
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          clockProvider.overrideWithValue(FixedClock(testNow)),
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
                categories: {SharingCategory.battery, SharingCategory.charging},
              ),
            ),
          ),
          partnerDeviceStateProvider.overrideWith(
            (ref) => Stream<PartnerDeviceState?>.value(
              partnerState == _unset
                  ? PartnerDeviceState(
                      testPartnerState(
                        chargingState: 'charging',
                        chargingDuration: const Duration(minutes: 250),
                        chargingStartedAt: testNow.subtract(
                          const Duration(minutes: 250),
                        ),
                      ),
                    )
                  : partnerState as PartnerDeviceState?,
            ),
          ),
          ...overrides,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  testWidgets('shows one card per matching interpretation', (tester) async {
    await pumpSection(
      tester,
      seed: [
        chargingRule(),
        chargingRule(
          id: 'rule-2',
          name: 'Battery high',
          output: RuleOutputKind.status,
          outputText: 'Battery is comfortable',
        ),
      ],
    );

    expect(find.text('What your rules say'), findsOneWidget);
    expect(find.byType(RuleInterpretationCard), findsNWidgets(2));
    expect(find.text('Possible sleep period'), findsOneWidget);
    // The badge names the kind of interpretation, the chip carries the value.
    expect(find.text('User-defined probability'), findsOneWidget);
    expect(find.text('User-defined probability: 70%'), findsOneWidget);
    expect(find.text('Battery is comfortable'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets(
    'an enabled rule that does not match shows nothing to interpret',
    (tester) async {
      await pumpSection(
        tester,
        seed: [chargingRule()],
        partnerState: PartnerDeviceState(
          testPartnerState(
            chargingDuration: const Duration(minutes: 10),
            chargingStartedAt: testNow.subtract(const Duration(minutes: 10)),
          ),
        ),
      );

      expect(find.byType(RuleInterpretationCard), findsNothing);
      expect(find.text('No rule applies right now'), findsOneWidget);
      expect(find.text('Possible sleep period'), findsNothing);
    },
  );

  testWidgets('a disabled rule produces no interpretation', (tester) async {
    await pumpSection(tester, seed: [chargingRule(enabled: false)]);

    expect(find.byType(RuleInterpretationCard), findsNothing);
    expect(find.text('No rule applies right now'), findsOneWidget);
  });

  testWidgets('no authorized partner state is explained, not left blank', (
    tester,
  ) async {
    await pumpSection(tester, seed: [chargingRule()], partnerState: null);

    expect(find.byType(RuleInterpretationCard), findsNothing);
    expect(find.text('Nothing to interpret yet'), findsOneWidget);
  });

  testWidgets('a rule that cannot be decided is shown as such', (tester) async {
    await pumpSection(
      tester,
      seed: [chargingRule()],
      // Nothing but a battery reading, so the charging duration is unknown.
      partnerState: PartnerDeviceState(testPartnerState(batteryPercentage: 60)),
    );

    expect(find.byType(RuleInterpretationCard), findsOneWidget);
    expect(find.text('Not enough information'), findsOneWidget);
    expect(find.textContaining('has not been shared'), findsOneWidget);
    expect(find.text('Based on your rule'), findsNothing);
  });

  testWidgets('unknown data is explained as unknown, not as a system failure', (
    tester,
  ) async {
    await pumpSection(
      tester,
      seed: [chargingRule(name: 'Left home')],
      // No location document at all.
      partnerState: PartnerDeviceState(testPartnerState()),
    );

    expect(find.byType(RuleInterpretationCard), findsOneWidget);
    expect(find.textContaining('has not been shared'), findsOneWidget);
    expect(find.textContaining('Something went wrong'), findsNothing);
  });

  testWidgets('shows a labelled wait while the rules load', (tester) async {
    await pumpSection(
      tester,
      seed: const <Rule>[],
      overrides: [
        rulesControllerProvider.overrideWith(_PendingRulesController.new),
      ],
      // The loading spinner never settles, so only pump frames.
      settle: false,
    );

    expect(find.text(RuleInterpretationsSection.loadingLabel), findsOneWidget);
    expect(find.byType(RuleInterpretationCard), findsNothing);
  });

  testWidgets('reports a failed rule read without inventing interpretations', (
    tester,
  ) async {
    await pumpSection(
      tester,
      seed: const <Rule>[],
      overrides: [
        rulesControllerProvider.overrideWith(_FailingRulesController.new),
      ],
    );

    expect(find.text('Your rules could not be checked'), findsOneWidget);
    expect(find.byType(RuleInterpretationCard), findsNothing);
  });

  testWidgets('a stale snapshot is labelled rather than presented as current', (
    tester,
  ) async {
    await pumpSection(
      tester,
      seed: [chargingRule()],
      partnerState: PartnerDeviceState(
        testPartnerState(
          observedAt: testNow.subtract(const Duration(hours: 3)),
          chargingDuration: const Duration(minutes: 250),
          chargingStartedAt: testNow.subtract(
            const Duration(hours: 3, minutes: 4),
          ),
        ),
      ),
    );

    expect(find.byType(RuleInterpretationCard), findsOneWidget);
    expect(find.textContaining('no longer current'), findsWidgets);
  });

  testWidgets('survives a narrow surface without overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSection(
      tester,
      seed: [
        chargingRule(
          name: 'A very long rule name that must wrap rather than overflow',
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });
}

/// Sentinel so `partnerState: null` is distinguishable from "not supplied".
const Object _unset = Object();
