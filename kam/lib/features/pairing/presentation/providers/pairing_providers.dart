import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/pairing_repository.dart';
import '../../domain/models/pair_membership.dart';
import '../../domain/models/partner_scope.dart';

export '../../domain/models/partner_scope.dart';

/// The pairing data layer, or `null` when Firebase is unavailable in this build.
final pairingRepositoryProvider = Provider<PairingRepository?>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) return null;
  return PairingRepository(ref.watch(firebaseFirestoreProvider));
});

/// Every pair the signed-in user belongs to.
final pairMembershipsProvider = StreamProvider<List<PairMembership>>((ref) {
  final uid = ref.watch(currentIdentityProvider)?.uid;
  final repository = ref.watch(pairingRepositoryProvider);
  if (uid == null || repository == null) {
    return Stream<List<PairMembership>>.value(const <PairMembership>[]);
  }
  return repository.watchPairMemberships(uid);
});

/// The active pair, or `null` when there is no authorized relationship.
///
/// This is asynchronous because it comes from Firestore: a UI must distinguish
/// "checking" from "there is no active pair" rather than assuming one or the
/// other.
final partnerScopeProvider = Provider<AsyncValue<PartnerScope?>>((ref) {
  final uid = ref.watch(currentIdentityProvider)?.uid;
  if (uid == null) {
    return const AsyncData<PartnerScope?>(null);
  }
  return ref.watch(pairMembershipsProvider).whenData((memberships) {
    for (final membership in memberships) {
      if (!membership.isActive) continue;
      final partnerUserId = membership.partnerOf(uid);
      if (partnerUserId == null) continue;
      return PartnerScope(
        pairId: membership.pairId,
        partnerUserId: partnerUserId,
      );
    }
    return null;
  });
});

/// The signed-in user's own consent decision for one pair, keyed by pair id.
///
/// `null` while undecided. The pairing screen uses this to replace the consent
/// buttons with a "waiting for the other person" state once this member has
/// decided, because a recorded consent cannot be changed and re-submitting it is
/// intentionally a no-op.
final ownConsentProvider = StreamProvider.family<bool?, String>((ref, pairId) {
  final uid = ref.watch(currentIdentityProvider)?.uid;
  final repository = ref.watch(pairingRepositoryProvider);
  if (uid == null || repository == null) {
    return Stream<bool?>.value(null);
  }
  return repository.watchOwnConsent(pairId: pairId, userId: uid);
});

/// The partner-visible display name, read only from this pair's member record.
final partnerDisplayNameProvider = StreamProvider<String?>((ref) {
  final scope = ref.watch(partnerScopeProvider).value;
  final repository = ref.watch(pairingRepositoryProvider);
  if (scope == null || repository == null) {
    return Stream<String?>.value(null);
  }
  return repository.watchPartnerDisplayName(
    pairId: scope.pairId,
    partnerUserId: scope.partnerUserId,
  );
});
