/// Who the authentication provider says the user is.
///
/// Deliberately **separate** from `AppUser` (the Firestore profile). Identity is
/// asserted by Firebase Authentication and always exists while signed in; the
/// profile document may be missing, unreadable or still loading. Conflating them
/// would force the app to invent a profile whenever identity exists, which the
/// SRS forbids (FR-048, NFR-006) — see
/// `docs/architecture/AUTHENTICATION_ARCHITECTURE.md` §2.
///
/// Pure Dart: no Firebase types, so routing, the UI and tests never depend on the
/// SDK (ADR-001, and the architecture test in `test/architecture/`).
class AuthIdentity {
  const AuthIdentity({
    required this.uid,
    this.email,
    this.emailVerified = false,
  });

  /// The provider-assigned user id (SRS FR-001).
  ///
  /// This is the **only** identifier for a user in the system: it is the
  /// `users/{uid}` document id, and every ownership rule compares it with
  /// `request.auth.uid`.
  final String uid;

  /// The account email, when the provider discloses it.
  final String? email;

  /// Whether the provider considers the email address verified.
  final bool emailVerified;

  @override
  bool operator ==(Object other) =>
      other is AuthIdentity &&
      other.uid == uid &&
      other.email == email &&
      other.emailVerified == emailVerified;

  @override
  int get hashCode => Object.hash(uid, email, emailVerified);

  /// Never prints the email: logs must not carry personal data (NFR-045).
  @override
  String toString() => 'AuthIdentity(uid: $uid)';
}
