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
      'code': code, 'createdByUserId': uid, 'revoked': false,
      'usedByUserId': null, 'status': 'created',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(now.toDate().add(const Duration(minutes: 20))),
    });
    return code;
  }

  Future<void> cancelInvitation(String code) => _db.collection('pairingCodes')
      .doc(code).update({'revoked': true, 'status': 'cancelled', 'revokedAt': FieldValue.serverTimestamp()});

  /// Redeems a known code into a pending pair; the code never activates access.
  Future<String> redeem(String code, String uid) async {
    final normalized = code.trim().toUpperCase();
    final hasValidFormat = normalized.length == 26 && normalized.codeUnits.every(
      (unit) => PairingCodeGenerator.alphabet.contains(String.fromCharCode(unit)),
    );
    if (!hasValidFormat) {
      throw const FormatException('Enter a valid pairing code.');
    }
    final codeRef = _db.collection('pairingCodes').doc(normalized);
    final pairRef = _db.collection('pairs').doc();
    try {
      await _db.runTransaction((tx) async {
        final invite = await tx.get(codeRef);
        if (!invite.exists) throw StateError('This pairing code is invalid, expired, or already used.');
        final data = invite.data()!;
        final creator = data['createdByUserId'] as String?;
        final expiry = data['expiresAt'] as Timestamp?;
        if (creator == null || expiry == null || creator == uid || data['revoked'] != false ||
            data['usedByUserId'] != null || !expiry.toDate().isAfter(DateTime.now())) {
          throw StateError('This pairing code is invalid, expired, or already used.');
        }
        tx.update(codeRef, {'usedByUserId': uid, 'usedAt': FieldValue.serverTimestamp(), 'status': 'consumed'});
        tx.set(pairRef, {
          'memberIds': [creator, uid]..sort(), 'status': 'pending',
          'requestedBy': uid, 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(), 'invitationCode': normalized,
          'schemaVersion': 1,
        });
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        throw StateError('This pairing code is invalid, expired, or already used.');
      }
      rethrow;
    }
    return pairRef.id;
  }

  Future<void> setConsent(String pairId, String uid, {required bool granted}) async {
    final consentRef = _db.collection('pairs').doc(pairId).collection('consents').doc(uid);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(consentRef);
      if (existing.exists) {
        if (existing.data()?['granted'] == granted) return;
        throw StateError('A recorded consent decision cannot be changed.');
      }
      tx.set(consentRef, {
        'userId': uid, 'pairId': pairId, 'granted': granted,
        'categories': <String>[], 'grantedAt': granted ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (!granted) {
      await _db.collection('pairs').doc(pairId).update({
        'status': 'revoked', 'endedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    await _activateIfConsented(pairId);
  }

  Future<void> _activateIfConsented(String pairId) async {
    final pairRef = _db.collection('pairs').doc(pairId);
    await _db.runTransaction((tx) async {
      final pair = await tx.get(pairRef);
      if (!pair.exists || pair.data()?['status'] != 'pending') return;
      final ids = List<String>.from(pair.data()!['memberIds'] as List);
      if (ids.length != 2) return;
      final consents = await Future.wait(ids.map((id) => tx.get(pairRef.collection('consents').doc(id))));
      if (!consents.every((c) => c.exists && c.data()?['granted'] == true)) return;
      tx.update(pairRef, {'status': 'active', 'activatedAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
      for (final id in ids) {
        tx.set(pairRef.collection('sharing').doc(id), {
          'userId': id, 'pairId': pairId, 'paused': false, 'categories': <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> disconnect(String pairId) => _db.collection('pairs').doc(pairId).update({
    'status': 'disconnected', 'endedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPairs(String uid) => _db
      .collection('pairs').where('memberIds', arrayContains: uid).snapshots();

  /// The caller's own pairs, as domain models.
  ///
  /// The query filters on the caller's own membership, so it can only ever
  /// return pairs the security rules already permit this user to read. Nothing
  /// here decides authorization: it only resolves what the user already has.
  Stream<List<PairMembership>> watchPairMemberships(String uid) => watchPairs(uid)
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) => PairMembership(
                pairId: document.id,
                memberIds: List<String>.from(
                  document.data()['memberIds'] as List? ?? const <String>[],
                ),
                status: document.data()['status'] as String? ?? 'unknown',
                isFromCache: document.metadata.isFromCache,
              ),
            )
            .where((membership) => membership.involves(uid))
            .toList(growable: false),
      );
}
