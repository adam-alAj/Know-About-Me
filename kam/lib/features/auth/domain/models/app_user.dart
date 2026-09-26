/// A user profile document (SRS FR-002).
///
/// This models exactly the `users/{uid}` document from
/// `docs/architecture/FIRESTORE_DATA_MODEL.md` §2 — nothing more. Fields that are
/// private (home location, notification preferences) live in the
/// `users/{uid}/settings/preferences` subdocument and are modelled separately by
/// `UserPreferences`, because the Security Rules enforce that split and a
/// partner-visible field must never be stored next to a private one.
///
/// Named [AppUser] to avoid colliding with Firebase's `User` type, and kept
/// separate from `AuthIdentity`: identity always exists while signed in, whereas
/// this document may be missing. A missing profile is represented by `null` at
/// the boundary, never by a synthesised instance (FR-048, NFR-006).
///
/// Pure Dart: no Firebase, Flutter or Riverpod types (ADR-001).
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.timeZone,
    this.createdAt,
    this.updatedAt,
  });

  /// The Firebase Authentication uid (FR-001). Also the document id.
  final String id;

  /// Display name shown to the owner and to a connected partner. Limited to
  /// [maxDisplayNameLength] characters by both the client and the Security Rules.
  final String displayName;

  /// Optional profile image reference.
  final String? photoUrl;

  /// IANA time-zone name used to render timestamps locally (NFR-026).
  final String? timeZone;

  /// Server timestamp of profile creation.
  final DateTime? createdAt;

  /// Server timestamp of the last profile change.
  final DateTime? updatedAt;

  /// Upper bound enforced by both the client validator and `firestore.rules`.
  static const int maxDisplayNameLength = 120;

  /// Returns a copy with the given fields replaced.
  ///
  /// Only user-editable fields are parameters: [id] and [createdAt] are
  /// deliberately absent so the client cannot even express an ownership or
  /// creation-time change (SRS Task 15, constraint: protected fields).
  AppUser copyWith({
    String? displayName,
    String? photoUrl,
    String? timeZone,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      timeZone: timeZone ?? this.timeZone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(id, displayName, photoUrl, timeZone);

  @override
  String toString() => 'AppUser($id, $displayName)';
}
