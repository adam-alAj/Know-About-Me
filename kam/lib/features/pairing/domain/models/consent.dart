import '../../../privacy/domain/models/sharing_category.dart';

/// What another user is asking to connect to and share (SRS FR-005).
///
/// Shown to the invited user before they grant consent.
class ConsentRequest {
  const ConsentRequest({
    required this.requestingUserId,
    required this.targetUserId,
    this.requestedCategories = const <SharingCategory>{},
    this.includesLocation = false,
  });

  final String requestingUserId;
  final String targetUserId;

  /// Categories the requester proposes to share.
  final Set<SharingCategory> requestedCategories;

  /// Whether location sharing is part of the request (FR-005).
  final bool includesLocation;

  @override
  String toString() =>
      'ConsentRequest($requestingUserId -> $targetUserId, '
      'location: $includesLocation)';
}

/// A single user's explicit decision about a pair.
///
/// Pairing is **not** authorization by itself (SRS NFR-003): completing a
/// pairing flow does not create a [Consent] implicitly. Both members must hold
/// an active consent before any device information is shared (FR-005, NFR-002).
class Consent {
  const Consent({
    required this.id,
    required this.userId,
    required this.pairId,
    required this.granted,
    this.grantedAt,
    this.revokedAt,
    this.sharedCategories = const <SharingCategory>{},
    this.locationSharingGranted = false,
  });

  final String id;
  final String userId;
  final String pairId;

  /// The user's explicit decision.
  final bool granted;

  final DateTime? grantedAt;
  final DateTime? revokedAt;

  /// Categories the user agreed to expose.
  final Set<SharingCategory> sharedCategories;

  /// Location is tracked separately because it is more sensitive (NFR-036).
  final bool locationSharingGranted;

  /// Whether this consent currently authorizes sharing.
  bool get isActive => granted && revokedAt == null;

  /// Whether [category] is authorized by both consent and the grant list.
  bool authorizes(SharingCategory category) =>
      isActive && sharedCategories.contains(category);

  @override
  String toString() =>
      'Consent(user: $userId, pair: $pairId, active: $isActive)';
}
