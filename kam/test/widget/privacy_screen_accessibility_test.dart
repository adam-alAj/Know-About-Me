import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/presentation/providers/sync_providers.dart';
import 'package:kam/features/pairing/presentation/providers/pairing_providers.dart';

import '../support/test_app.dart';

void main() {
  const scope = PartnerScope(pairId: 'pair-a', partnerUserId: 'user-b');

  testWidgets(
    'sharing controls stay read-only when settings cannot be confirmed',
    (tester) async {
      final sharingController = StreamController<PairSharingState>();
      await pumpTestApp(
        tester,
        overrides: [
          partnerScopeProvider.overrideWithValue(const AsyncData(scope)),
          ownSharingProvider.overrideWith((ref) => sharingController.stream),
        ],
      );
      await tester.tap(find.text('Privacy'));
      // The initial privacy state intentionally shows an indeterminate loader,
      // so pump a bounded transition interval instead of waiting for animations
      // to settle forever.
      await tester.pump(const Duration(milliseconds: 500));
      sharingController.addError(StateError('unavailable'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(
        find.text(
          'Settings are read-only until your current sharing choices can be confirmed.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sharing settings could not be confirmed'),
        findsOneWidget,
      );
      final toggles = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(toggles, isNotEmpty);
      expect(toggles.every((toggle) => toggle.onChanged == null), isTrue);
      await sharingController.close();
    },
  );

  testWidgets('confirmed privacy settings expose labelled controls', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      overrides: [
        partnerScopeProvider.overrideWithValue(const AsyncData(scope)),
        ownSharingProvider.overrideWith(
          (ref) => Stream.value(
            const PairSharingState(paused: false, categories: {}),
          ),
        ),
      ],
    );
    await tester.tap(find.text('Privacy'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('What you share'), findsOneWidget);
    expect(find.text('Pause all sharing'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    final toggles = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(toggles.every((toggle) => toggle.onChanged != null), isTrue);
  });
}
