import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/device_event.dart';

/// Pair-scoped append-only history. Deterministic document IDs make retries
/// idempotent; Firestore server time is assigned only on first creation.
class FirestoreHistoryRepository {
  FirestoreHistoryRepository(this._db);
  final FirebaseFirestore _db;

  Future<void> deleteOwnedHistory({required String pairId, required String ownerUserId}) async {
    final collection = _db.collection('pairs').doc(pairId).collection('events');
    while (true) {
      final page = await collection.where('ownerUserId', isEqualTo: ownerUserId).limit(200).get();
      if (page.docs.isEmpty) return;
      final batch = _db.batch();
      for (final document in page.docs) { batch.delete(document.reference); }
      await batch.commit();
    }
  }

  Future<void> add(DeviceEvent event) async {
    final reference = _db.collection('pairs').doc(event.pairId)
        .collection('events').doc(event.id);
    final data = event.toJson(includeRecordedAt: false)
      ..remove('id')
      ..['occurredAt'] = Timestamp.fromDate(event.occurredAt.toUtc())
      ..remove('pairId')
      ..remove('deviceId')
      ..['recordedAt'] = FieldValue.serverTimestamp();
    if (event.observedAt != null) data['observedAt'] = Timestamp.fromDate(event.observedAt!.toUtc());
    try {
      // Rules permit creation but reject updates, so retries with this stable
      // document ID cannot overwrite the original event.
      await reference.set(data);
    } on FirebaseException catch (error) {
      // An existing document is denied as an update. Keep the cached event;
      // the create-only rule is the final deduplication boundary.
      if (error.code != 'permission-denied') rethrow;
    }
  }

  Stream<List<DeviceEvent>> watch({required String pairId, EventCategory? category, int limit = 50}) {
    Query<Map<String, dynamic>> query = _db.collection('pairs').doc(pairId)
        .collection('events').orderBy('recordedAt', descending: true);
    if (category != null) query = query.where('category', isEqualTo: category.name);
    return query.limit(limit.clamp(1, 100).toInt()).snapshots().map((snapshot) {
      final events = <DeviceEvent>[];
      for (final document in snapshot.docs) {
        try {
          final data = Map<String, Object?>.from(document.data());
          data['id'] = document.id;
          data['pairId'] = pairId;
          data['deviceId'] = '';
          final recordedAt = document.data()['recordedAt'];
          if (recordedAt is Timestamp) data['recordedAt'] = recordedAt.toDate().toUtc().toIso8601String();
          final occurredAt = document.data()['occurredAt'];
          if (occurredAt is Timestamp) data['occurredAt'] = occurredAt.toDate().toUtc().toIso8601String();
          final observedAt = document.data()['observedAt'];
          if (observedAt is Timestamp) data['observedAt'] = observedAt.toDate().toUtc().toIso8601String();
          events.add(DeviceEvent.fromJson(data));
        } on Object {
          // Ignore a malformed document while preserving valid timeline items.
        }
      }
      events.sort((a, b) {
        final order = (b.recordedAt ?? b.occurredAt).compareTo(a.recordedAt ?? a.occurredAt);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
      return events;
    });
  }
}
