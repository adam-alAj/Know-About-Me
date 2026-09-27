/// One pair as this device is allowed to see it.
///
/// This is the *only* input from which the synchronization layer resolves which
/// pair to write to and which partner to read (Phase 11 §22). It is derived from
/// an authenticated query over the caller's own membership, so a screen cannot
/// substitute an arbitrary pair id.
class PairMembership {
  const PairMembership({
    required this.pairId,
    required this.memberIds,
    required this.status,
    this.isFromCache = false,
  });

  final String pairId;

  /// Both member user ids, exactly as stored on the pair document.
  final List<String> memberIds;

  /// The stored status string: `pending`, `active`, `paused`, `disconnected` or
  /// `revoked`. Kept as the raw server value so the UI never has to guess.
  final String status;

  /// Whether Firestore served this from its local cache.
  ///
  /// A cached `active` status is not proof that the relationship is still
  /// active; the security rules re-check on every read and write, so a stale
  /// cache can only ever produce a rejected request, never unauthorized access.
  final bool isFromCache;

  /// Whether the pair may currently share.
  bool get isActive => status == 'active';

  /// Whether consent has not yet been decided by both members.
  bool get isPending => status == 'pending';

  /// Whether the relationship has ended.
  bool get isEnded => status == 'disconnected' || status == 'revoked';

  /// Whether [userId] is one of the two members.
  bool involves(String userId) => memberIds.contains(userId);

  /// The other member's user id, or `null` when this device is not a member.
  String? partnerOf(String userId) {
    for (final memberId in memberIds) {
      if (memberId != userId) return memberId;
    }
    return null;
  }

  @override
  String toString() =>
      'PairMembership($pairId, $status, cached: $isFromCache)';
}
