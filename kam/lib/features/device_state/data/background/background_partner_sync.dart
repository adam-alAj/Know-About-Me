import 'package:cloud_firestore/cloud_firestore.dart';

/// Performs a short, authenticated Firestore catch-up without Riverpod.
///
/// Firestore's persistent cache is warmed by server reads. The foreground
/// providers parse and display the same documents when the app resumes.
class BackgroundPartnerSync {
  BackgroundPartnerSync(this._firestore);

  final FirebaseFirestore _firestore;

  static const _deviceStateCategories = <String>{
    'battery',
    'charging',
    'network',
    'activityIndicators',
  };

  Future<void> refreshSharedStateFor(String signedInUserId) async {
    final pairSnapshots = await _firestore
        .collection('pairs')
        .where('memberIds', arrayContains: signedInUserId)
        .get(const GetOptions(source: Source.server));

    for (final pairSnapshot in pairSnapshots.docs) {
      final pairData = pairSnapshot.data();
      final members = List<String>.from(
        pairData['memberIds'] as List? ?? const [],
      );
      if (pairData['status'] != 'active' ||
          members.length != 2 ||
          !members.contains(signedInUserId)) {
        continue;
      }

      final partnerId = members.firstWhere(
        (memberId) => memberId != signedInUserId,
      );
      final pair = pairSnapshot.reference;
      final consentSnapshots = await Future.wait(
        members.map(
          (memberId) => pair
              .collection('consents')
              .doc(memberId)
              .get(const GetOptions(source: Source.server)),
        ),
      );
      if (consentSnapshots.any(
        (consent) => consent.data()?['granted'] != true,
      )) {
        continue;
      }

      final sharingSnapshot = await pair
          .collection('sharing')
          .doc(partnerId)
          .get(const GetOptions(source: Source.server));
      final sharing = sharingSnapshot.data();
      if (sharing == null || sharing['paused'] != false) continue;

      final categories = Set<String>.from(
        sharing['categories'] as List? ?? const [],
      );
      if (categories.intersection(_deviceStateCategories).isNotEmpty) {
        await pair
            .collection('deviceState')
            .doc(partnerId)
            .get(const GetOptions(source: Source.server));
      }
      if (categories.contains('location')) {
        await pair
            .collection('location')
            .doc(partnerId)
            .get(const GetOptions(source: Source.server));
      }
    }
  }
}
