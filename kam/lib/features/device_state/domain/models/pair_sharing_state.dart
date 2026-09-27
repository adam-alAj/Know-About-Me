import '../../../privacy/domain/models/sharing_category.dart';

/// One member's live sharing switches for one pair.
///
/// This mirrors `pairs/{pairId}/sharing/{userId}`: a single document per
/// (pair, user), so there is exactly one source of truth for "am I sharing this
/// right now" and the client and the security rules cannot disagree.
///
/// Consent decides whether a relationship may share at all; this decides what is
/// shared at the moment, and can be paused without disconnecting (SRS FR-052,
/// FR-053).
class PairSharingState {
  const PairSharingState({
    required this.paused,
    required this.categories,
  });

  /// Nothing has been configured yet: share nothing.
  ///
  /// Fail-closed, so a missing document can never be read as "share
  /// everything".
  static const PairSharingState none = PairSharingState(
    paused: true,
    categories: <SharingCategory>{},
  );

  /// Whether all categories are withheld regardless of [categories].
  final bool paused;

  final Set<SharingCategory> categories;

  /// Whether [category] may currently be transmitted.
  bool shares(SharingCategory category) =>
      !paused && categories.contains(category);

  /// Whether anything at all may be transmitted.
  bool get sharesAnything => !paused && categories.isNotEmpty;

  /// Whether [owner] may see [category] of their partner, for the client-side
  /// eligibility checks that run *before* a write is attempted.
  ///
  /// The security rules remain the authoritative check; this only avoids
  /// predictable permission failures.
  bool isReadable(SharingCategory category) => shares(category);

  /// The category names as stored in Firestore.
  List<String> get categoryNames =>
      categories.map((category) => category.name).toList()..sort();

  @override
  String toString() =>
      'PairSharingState(paused: $paused, categories: ${categories.length})';
}
