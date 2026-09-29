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
    this.isFromCache = false,
    this.hasPendingWrites = false,
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

  /// A cached sharing record is the last known setting, not proof of current
  /// authorization while this device is offline.
  final bool isFromCache;

  /// Whether this device holds a local write for the sharing document that the
  /// server has not acknowledged yet.
  ///
  /// The distinction between a *decision* and the *last known value* matters
  /// offline. A pending local write is the user's own latest decision and must
  /// take effect locally at once, even though the server has not confirmed it
  /// (Phase 20 §11). A cache-only value with no pending write is merely the last
  /// setting this device saw, so it must not be turned into a new decision.
  final bool hasPendingWrites;

  /// Whether this snapshot reflects a decision rather than the last known value:
  /// the server confirmed it, or it carries our own unacknowledged local write.
  bool get isConfirmed => !isFromCache || hasPendingWrites;

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
      'PairSharingState(paused: $paused, categories: ${categories.length}, '
      'cached: $isFromCache, pending: $hasPendingWrites)';
}
