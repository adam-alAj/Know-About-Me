import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../privacy/domain/models/sharing_category.dart';
import '../../domain/models/pair_sharing_state.dart';
import '../../domain/repositories/sharing_repository.dart';

/// Firestore implementation of [SharingRepository] over
/// `pairs/{pairId}/sharing/{userId}`.
///
/// The document is per (pair, user) so there is exactly one source of truth for
/// "am I sharing this right now", and the security rules can decide a partner
/// read with a single extra lookup.
class FirestoreSharingRepository implements SharingRepository {
  FirestoreSharingRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<PairSharingState> watch({
    required String pairId,
    required String userId,
  }) {
    return _document(pairId, userId)
        // Metadata changes are observed explicitly: a cache-served sharing
        // document that the server later confirms with identical data would
        // otherwise never re-emit, and the connection would look offline and
        // the sharing state permanently unconfirmed (Phase 20 §9, §11).
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) return PairSharingState.none;
          return PairSharingState(
            paused: data['paused'] == true,
            categories: _categories(data['categories']),
            isFromCache: snapshot.metadata.isFromCache,
            // A local, unacknowledged write is the user's own latest decision. It
            // must be applied immediately offline (Phase 20 §11).
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          );
        })
        .handleError((Object _) {
          // An unreadable sharing document is not an error the user can act on, and
          // it must never be interpreted as "everything is shared": fail closed.
          return PairSharingState.none;
        });
  }

  @override
  Future<void> setSharing({
    required String pairId,
    required String userId,
    required bool paused,
    required Set<SharingCategory> categories,
  }) async {
    await _document(pairId, userId).set({
      'userId': userId,
      'pairId': pairId,
      'paused': paused,
      'categories': categories.map((category) => category.name).toList()
        ..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _document(
    String pairId,
    String userId,
  ) => _db.collection('pairs').doc(pairId).collection('sharing').doc(userId);

  /// Unknown category names are dropped rather than guessed at, so a document
  /// written by a newer build cannot silently widen what this build shares.
  static Set<SharingCategory> _categories(Object? raw) {
    if (raw is! List) return const <SharingCategory>{};
    final result = <SharingCategory>{};
    for (final name in raw.whereType<String>()) {
      for (final category in SharingCategory.values) {
        if (category.name == name) result.add(category);
      }
    }
    return result;
  }
}
