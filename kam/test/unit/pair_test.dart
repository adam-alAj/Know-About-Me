import 'package:flutter_test/flutter_test.dart';

import 'package:kam/features/pairing/domain/models/connection_status.dart';
import 'package:kam/features/pairing/domain/models/consent.dart';
import 'package:kam/features/pairing/domain/models/pair.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';
import 'package:kam/features/privacy/domain/models/sharing_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26, 12);

  Pair buildPair() => const Pair(
    id: 'pair-1',
    memberAUserId: 'user-a',
    memberBUserId: 'user-b',
    lifecycle: PairLifecycleState.requested,
  );

  group('Pair lifecycle', () {
    test('accepts legal transitions', () {
      expect(
        PairLifecycleState.requested.canTransitionTo(
          PairLifecycleState.accepted,
        ),
        isTrue,
      );
      expect(
        PairLifecycleState.accepted.canTransitionTo(PairLifecycleState.active),
        isTrue,
      );
      expect(
        PairLifecycleState.active.canTransitionTo(PairLifecycleState.paused),
        isTrue,
      );
    });

    test('rejects illegal transitions', () {
      expect(
        PairLifecycleState.created.canTransitionTo(PairLifecycleState.active),
        isFalse,
      );
      expect(
        PairLifecycleState.revoked.canTransitionTo(PairLifecycleState.active),
        isFalse,
      );
      expect(
        () => buildPair().transitionTo(PairLifecycleState.active),
        throwsA(isA<StateError>()),
      );
    });

    test('maps lifecycle to the user-facing connection status', () {
      expect(
        PairLifecycleState.active.connectionStatus,
        ConnectionStatus.connected,
      );
      expect(
        PairLifecycleState.paused.connectionStatus,
        ConnectionStatus.temporarilyPaused,
      );
      expect(
        PairLifecycleState.revoked.connectionStatus,
        ConnectionStatus.revoked,
      );
    });
  });

  group('Pair isolation', () {
    test('resolves the partner only for a member', () {
      expect(buildPair().partnerOf('user-a'), 'user-b');
      expect(buildPair().partnerOf('user-b'), 'user-a');
    });

    test('an unrelated user cannot resolve a partner', () {
      expect(
        () => buildPair().partnerOf('user-c'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Consent is separate from pairing', () {
    test('entering a pairing code does not grant consent', () {
      final code = PairingCode(
        code: '482913',
        createdByUserId: 'user-a',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
      );

      expect(code.isUsableAt(now), isTrue);
      // The code itself carries no sharing authorization of any kind.
      expect(code, isNot(isA<Consent>()));
    });

    test('a granted consent authorizes only its listed categories', () {
      final consent = Consent(
        id: 'consent-1',
        userId: 'user-b',
        pairId: 'pair-1',
        granted: true,
        grantedAt: now,
        sharedCategories: const {SharingCategory.battery},
      );

      expect(consent.isActive, isTrue);
      expect(consent.authorizes(SharingCategory.battery), isTrue);
      expect(consent.authorizes(SharingCategory.location), isFalse);
    });

    test('a revoked consent authorizes nothing', () {
      final consent = Consent(
        id: 'consent-1',
        userId: 'user-b',
        pairId: 'pair-1',
        granted: true,
        grantedAt: now,
        revokedAt: now,
        sharedCategories: const {SharingCategory.battery},
      );

      expect(consent.isActive, isFalse);
      expect(consent.authorizes(SharingCategory.battery), isFalse);
    });
  });

  group('Sharing preferences', () {
    test('pausing withholds every category regardless of selection', () {
      const prefs = SharingPreferences(
        userId: 'user-a',
        pairId: 'pair-1',
        sharingPaused: true,
        enabledCategories: {SharingCategory.battery, SharingCategory.location},
      );

      expect(prefs.isCategoryShared(SharingCategory.battery), isFalse);
      expect(prefs.isCategoryShared(SharingCategory.location), isFalse);
    });

    test('a category can be toggled without pausing the pair', () {
      const prefs = SharingPreferences(
        userId: 'user-a',
        pairId: 'pair-1',
        enabledCategories: {SharingCategory.battery},
      );

      final withoutBattery = prefs.withCategory(SharingCategory.battery, false);

      expect(withoutBattery.isCategoryShared(SharingCategory.battery), isFalse);
      expect(withoutBattery.sharingPaused, isFalse);
    });
  });

  group('AppConfig/clock wiring sanity', () {
    test('pair partner lookup is symmetric', () {
      final pair = buildPair();
      expect(pair.involves('user-a'), isTrue);
      expect(pair.partnerOf(pair.partnerOf('user-a')), 'user-a');
    });
  });
}
