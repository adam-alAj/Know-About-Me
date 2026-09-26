import 'connection_status.dart';

/// A short-lived code used to initiate a connection (SRS FR-003, FR-004).
///
/// The code is a discovery mechanism only: possessing it must never grant
/// access to private device information (FR-003).
class PairingCode {
  const PairingCode({
    required this.code,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
    this.revoked = false,
  });

  final String code;
  final String createdByUserId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool used;
  final bool revoked;

  /// A code is usable only while unexpired, unused and not revoked.
  bool isUsableAt(DateTime now) =>
      !used && !revoked && now.toUtc().isBefore(expiresAt.toUtc());

  @override
  String toString() => 'PairingCode(createdBy: $createdByUserId, used: $used)';
}

/// A mutual relationship between exactly two users (SRS 1.2, Task 9: `Pair`).
class Pair {
  const Pair({
    required this.id,
    required this.memberAUserId,
    required this.memberBUserId,
    required this.lifecycle,
    this.createdAt,
    this.activatedAt,
    this.endedAt,
  }) : assert(
         memberAUserId != memberBUserId,
         'A pair always joins two distinct users',
       );

  final String id;
  final String memberAUserId;
  final String memberBUserId;
  final PairLifecycleState lifecycle;

  final DateTime? createdAt;

  /// When both consents were granted and the pair became active.
  final DateTime? activatedAt;

  /// When the pair was revoked or disconnected.
  final DateTime? endedAt;

  /// Whether [userId] is one of the two members.
  bool involves(String userId) =>
      userId == memberAUserId || userId == memberBUserId;

  /// The other member's user id.
  ///
  /// Throws [ArgumentError] if [userId] is not a member, which prevents an
  /// unrelated user from ever resolving a partner (FR-064).
  String partnerOf(String userId) {
    if (userId == memberAUserId) return memberBUserId;
    if (userId == memberBUserId) return memberAUserId;
    throw ArgumentError.value(userId, 'userId', 'Not a member of pair $id');
  }

  /// Whether the pair is currently sharing-capable.
  bool get isActive => lifecycle == PairLifecycleState.active;

  /// Returns a copy moved to [next], rejecting illegal transitions (NFR-042).
  Pair transitionTo(PairLifecycleState next, {DateTime? at}) {
    if (!lifecycle.canTransitionTo(next)) {
      throw StateError(
        'Illegal pair transition: ${lifecycle.name} -> ${next.name}',
      );
    }
    return Pair(
      id: id,
      memberAUserId: memberAUserId,
      memberBUserId: memberBUserId,
      lifecycle: next,
      createdAt: createdAt,
      activatedAt: next == PairLifecycleState.active
          ? (at ?? activatedAt)
          : activatedAt,
      endedAt:
          next == PairLifecycleState.revoked ||
              next == PairLifecycleState.disconnected
          ? (at ?? endedAt)
          : endedAt,
    );
  }

  @override
  String toString() => 'Pair($id, ${lifecycle.name})';
}
