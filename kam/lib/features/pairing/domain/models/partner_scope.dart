/// The pair this device is allowed to synchronize within.
///
/// Both values are resolved from authenticated application state — the user's
/// own pair membership plus the authenticated uid — and never from a screen
/// argument. That is what prevents a modified client from pointing a write or a
/// listener at another person's documents (Phase 11 §22, §50).
class PartnerScope {
  const PartnerScope({required this.pairId, required this.partnerUserId});

  final String pairId;
  final String partnerUserId;

  @override
  bool operator ==(Object other) =>
      other is PartnerScope &&
      other.pairId == pairId &&
      other.partnerUserId == partnerUserId;

  @override
  int get hashCode => Object.hash(pairId, partnerUserId);

  @override
  String toString() => 'PartnerScope(pair: $pairId)';
}
