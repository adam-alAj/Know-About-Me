import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/pair_membership.dart';
import '../domain/pairing_code_generator.dart';

/// Spark-compatible pairing operations. Rules, not these checks, authorize writes.
class PairingRepository {
  PairingRepository(this._db);
  final FirebaseFirestore _db;
  final PairingCodeGenerator _codes = PairingCodeGenerator();

  Future<String> createInvitation(String uid) async {
    final code = _codes.generate();
    final now = Timestamp.now();
    await _db.collection('pairingCodes').doc(code).set({
      'code': code,
      'createdByUserId': uid,
      'revoked': false,
      'usedByUserId': null,
      'status': 'created',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        now.toDate().add(const Duration(minutes: 20)),
      ),
    });
    return code;
  }

  Future<void> cancelInvitation(String code) =>
      _db.collection('pairingCodes').doc(code).update({
        'revoked': true,
        'status': 'cancelled',
        'revokedAt': FieldValue.serverTimestamp(),
      });

  /// Redeems a known code into a pending pair; the code never activates access.
  Future<String> redeem(String code, String uid) async {
    final normalized = code.trim().toUpperCase();
    final hasValidFormat =
        normalized.length == 26 &&
        normalized.codeUnits.every(
          (unit) =>
              PairingCodeGenerator.alphabet.contains(String.fromCharCode(unit)),
        );
    if (!hasValidFormat) {
      throw const FormatException('Enter a valid pairing code.');
    }
    final codeRef = _db.collection('pairingCodes').doc(normalized);
    final pairRef = _db.collection('pairs').doc();
    try {
      await _db.runTransaction((tx) async {
        final invite = await tx.get(codeRef);
        if (!invite.exists) {
          throw StateError(
            'This pairing code is invalid, expired, or already used.',
          );
        }
        final data = invite.data()!;
        final creator = data['createdByUserId'] as String?;
        final expiry = data['expiresAt'] as Timestamp?;
        if (creator == null ||
            expiry == null ||
            creator == uid ||
            data['revoked'] != false ||
            data['usedByUserId'] != null ||
            !expiry.toDate().isAfter(DateTime.now())) {
          throw StateError(
            'This pairing code is invalid, expired, or already used.',
          );
        }
        tx.update(codeRef, {
          'usedByUserId': uid,
          'usedAt': FieldValue.serverTimestamp(),
          'status': 'consumed',
        });
        tx.set(pairRef, {
          'memberIds': [creator, uid]..sort(),
          'status': 'pending',
          'requestedBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'invitationCode': normalized,
          'schemaVersion': 1,
        });
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        throw StateError(
          'This pairing code is invalid, expired, or already used.',
        );
      }
      rethrow;
    }
    return pairRef.id;
  }

  Future<void> setConsent(
    String pairId,
    String uid, {
    required bool granted,
  }) async {
    final consentRef = _db
        .collection('pairs')
        .doc(pairId)
        .collection('consents')
        .doc(uid);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(consentRef);
      if (existing.exists) {
        if (existing.data()?['granted'] == granted) return;
        throw StateError('A recorded consent decision cannot be changed.');
      }
      tx.set(consentRef, {
        'userId': uid,
        'pairId': pairId,
        'granted': granted,
        'categories': <String>[],
        'grantedAt': granted ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (!granted) {
      await _db.collection('pairs').doc(pairId).update({
        'status': 'revoked',
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    // Each member records their own live-sharing switch. The rules only allow a
    // user to write the sharing document named after themselves, so it cannot be
    // created on a member's behalf at activation time (see `sharing` in
    // firestore.rules). Creating it here guarantees both records exist by the
    // moment the pair becomes active.
    await _ensureOwnSharing(pairId, uid);
    try {
      await _syncOwnPairProfile(pairId, uid);
    } on FirebaseException {
      // Profile display is optional. A copy failure must not undo or obscure a
      // consent decision that Firestore has already recorded.
    }
    await _activateIfConsented(pairId);
  }

  /// Creates (or leaves unchanged) this member's own sharing document so the
  /// partner's reads have a live switch to check. Never writes another member's
  /// record: the rules bind `sharing/{uid}` to `request.auth.uid`.
  Future<void> _ensureOwnSharing(String pairId, String uid) =>
      _db
          .collection('pairs')
          .doc(pairId)
          .collection('sharing')
          .doc(uid)
          .set({
            'userId': uid,
            'pairId': pairId,
            'paused': false,
            'categories': <String>[],
            'updatedAt': FieldValue.serverTimestamp(),
          });

  /// Copies only the user's partner-approved display name into the pair-scoped
  /// member record. The partner never receives access to `users/{uid}`.
  Future<void> _syncOwnPairProfile(String pairId, String uid) async {
    final profile = await _db.collection('users').doc(uid).get();
    final displayName = profile.data()?['displayName'];
    if (displayName is! String || displayName.trim().isEmpty) return;
    await _db
        .collection('pairs')
        .doc(pairId)
        .collection('members')
        .doc(uid)
        .set({'displayName': displayName.trim()}, SetOptions(merge: true));
  }

  Future<void> _activateIfConsented(String pairId) async {
    final pairRef = _db.collection('pairs').doc(pairId);
    await _db.runTransaction((tx) async {
      final pair = await tx.get(pairRef);
      if (!pair.exists || pair.data()?['status'] != 'pending') return;
      final ids = List<String>.from(pair.data()!['memberIds'] as List);
      if (ids.length != 2) return;
      final consents = await Future.wait(
        ids.map((id) => tx.get(pairRef.collection('consents').doc(id))),
      );
      if (!consents.every((c) => c.exists && c.data()?['granted'] == true)) {
        return;
      }
      // Activation only flips the pair status. Each member's sharing document
      // is written by that member during their own consent, because the rules
      // forbid writing a sharing record that is not named after the caller.
      tx.update(pairRef, {
        'status': 'active',
        'activatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> disconnect(String pairId) => _endPair(pairId, 'disconnected');

  /// Permanently withdraws consent for this relationship. A new pairing and
  /// fresh consent are required before sharing can resume.
  Future<void> revoke(String pairId) => _endPair(pairId, 'revoked');

  Future<void> _endPair(String pairId, String status) =>
      _db.collection('pairs').doc(pairId).update({
        'status': status,
        'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPairs(String uid) => _db
      .collection('pairs')
      .where('memberIds', arrayContains: uid)
      .snapshots();

  /// Watches the caller's own consent decision for one pair.
  ///
  /// `null` means no decision has been recorded yet. Consent is immutable once
  /// recorded, so a decided value never changes. Lets the UI stop offering the
  /// consent buttons after this member has already decided.
  Stream<bool?> watchOwnConsent({
    required String pairId,
    required String userId,
  }) => _db
      .collection('pairs')
      .doc(pairId)
      .collection('consents')
      .doc(userId)
      .snapshots()
      .map((snapshot) {
        final granted = snapshot.data()?['granted'];
        return granted is bool ? granted : null;
      });

  /// Watches only the partner-visible profile stored inside this pair.
  /// Private `users/{uid}` profiles are never queried for another user.
  Stream<String?> watchPartnerDisplayName({
    required String pairId,
    required String partnerUserId,
  }) => _db
      .collection('pairs')
      .doc(pairId)
      .collection('members')
      .doc(partnerUserId)
      .snapshots()
      .map((snapshot) {
        final name = snapshot.data()?['displayName'];
        return name is String && name.trim().isNotEmpty ? name.trim() : null;
      });

  /// The caller's own pairs, as domain models.
  ///
  /// The query filters on the caller's own membership, so it can only ever
  /// return pairs the security rules already permit this user to read. Nothing
  /// here decides authorization: it only resolves what the user already has.
  Stream<List<PairMembership>> watchPairMemberships(String uid) =>
      watchPairs(uid).map(
        (snapshot) => snapshot.docs
            .map(
              (document) => PairMembership(
                pairId: document.id,
                memberIds: List<String>.from(
                  document.data()['memberIds'] as List? ?? const <String>[],
                ),
                status: document.data()['status'] as String? ?? 'unknown',
                isFromCache: document.metadata.isFromCache,
                hasPendingWrites: document.metadata.hasPendingWrites,
              ),
            )
            .where((membership) => membership.involves(uid))
            .toList(growable: false),
      );
}
