import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/state_observation.dart';
import 'package:kam/features/device_state/presentation/providers/sync_providers.dart';
import 'package:kam/features/pairing/domain/models/pair_membership.dart';
import 'package:kam/features/pairing/presentation/providers/pairing_providers.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('shows pairing guidance when no active pair exists', (tester) async {
    await pumpTestApp(
      tester,
      overrides: [
        pairMembershipsProvider.overrideWith(
          (ref) => Stream.value(const <PairMembership>[]),
        ),
      ],
    );

    expect(find.text('No active connection'), findsOneWidget);
    expect(find.text('Connect with partner'), findsOneWidget);
    expect(find.text('Your partner'), findsNothing);
  });

  testWidgets('hides partner data after a pair has ended', (tester) async {
    await pumpTestApp(
      tester,
      overrides: [
        pairMembershipsProvider.overrideWith(
          (ref) => Stream.value(const [
            PairMembership(
              pairId: 'pair-a',
              memberIds: ['user-a', 'user-b'],
              status: 'revoked',
            ),
          ]),
        ),
      ],
    );

    expect(find.text('Connection unavailable'), findsOneWidget);
    expect(find.textContaining('Partner dashboard'), findsNothing);
    expect(find.text('Your partner'), findsNothing);
  });

  testWidgets('shows stale state as last observed and hides disabled categories', (tester) async {
    final now = DateTime.now().toUtc();
    final state = RemoteDeviceState(
      pairId: 'pair-a',
      ownerUserId: 'user-b',
      observations: {
        DeviceMetric.batteryPercentage: StateObservation<Object?>(
          availability: CapabilityAvailability.available,
          value: 72,
          observedAt: now.subtract(const Duration(hours: 1)),
        ),
      },
      schemaVersion: 1,
      receivedAt: now,
      isFromCache: false,
      observedAt: now.subtract(const Duration(hours: 1)),
    );

    await pumpTestApp(
      tester,
      overrides: [
        pairMembershipsProvider.overrideWith(
          (ref) => Stream.value(const [
            PairMembership(
              pairId: 'pair-a',
              memberIds: ['user-a', 'user-b'],
              status: 'active',
            ),
          ]),
        ),
        partnerScopeProvider.overrideWithValue(
          const AsyncData<PartnerScope?>(
            PartnerScope(pairId: 'pair-a', partnerUserId: 'user-b'),
          ),
        ),
        partnerDisplayNameProvider.overrideWith((ref) => Stream.value('Nadia')),
        partnerSharingProvider.overrideWith(
          (ref) => Stream.value(const PairSharingState(
            paused: false,
            categories: {SharingCategory.battery},
          )),
        ),
        partnerDeviceStateProvider.overrideWith(
          (ref) => Stream.value(PartnerDeviceState(state)),
        ),
      ],
    );

    expect(find.text('Nadia'), findsOneWidget);
    expect(find.textContaining('Stale'), findsWidgets);
    expect(find.text('Battery'), findsWidgets);
    expect(find.text('72% · stale'), findsOneWidget);
    expect(find.text('Location & home'), findsNothing);
    expect(find.textContaining('user-b'), findsNothing);
  });
}

