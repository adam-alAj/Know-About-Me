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
