import 'sharing_category.dart';

/// A user's sharing choices for one pair.
///
/// Consent (see `Consent`) establishes *whether* a relationship may share at
/// all; [SharingPreferences] control *what* is currently shared and can be
/// changed at any time (SRS FR-052, FR-053).
class SharingPreferences {
  const SharingPreferences({
    required this.userId,
    required this.pairId,
    this.sharingPaused = false,
    this.enabledCategories = const <SharingCategory>{},
    this.updatedAt,
  });

  final String userId;
  final String pairId;

  /// When true, all categories are withheld regardless of [enabledCategories].
  ///
  /// The partner must be shown that sharing is paused rather than the last
  /// known state as if it were current (FR-053).
  final bool sharingPaused;

  final Set<SharingCategory> enabledCategories;
  final DateTime? updatedAt;

  /// Whether [category] may currently be transmitted to the partner.
  bool isCategoryShared(SharingCategory category) =>
      !sharingPaused && enabledCategories.contains(category);

  /// Returns a copy with [category] enabled or disabled.
  SharingPreferences withCategory(SharingCategory category, bool enabled) {
    final next = Set<SharingCategory>.of(enabledCategories);
    if (enabled) {
      next.add(category);
    } else {
      next.remove(category);
    }
    return SharingPreferences(
      userId: userId,
      pairId: pairId,
      sharingPaused: sharingPaused,
      enabledCategories: next,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'SharingPreferences(user: $userId, pair: $pairId, '
      'paused: $sharingPaused, categories: ${enabledCategories.length})';
}
