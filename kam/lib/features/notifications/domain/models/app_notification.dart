/// Category of a notification, used for filtering and preferences.
enum NotificationCategory {
  ruleInterpretation,
  deviceStateChange,
  connectionChange,
  sharingChange,
  system,
}

/// A delivered or deliverable notification (SRS FR-041 – FR-044).
///
/// Even when a push cannot be delivered, the record remains and the underlying
/// rule event stays in history (FR-044).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientUserId,
    required this.pairId,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.ruleId,
    this.delivered = false,
    this.read = false,
  });

  final String id;
  final String recipientUserId;
  final String pairId;

  /// Short title. Must not expose unnecessary private information (FR-043).
  final String title;

  /// Message body, for example
  /// "There is a 70% possibility that Afraa is sleeping now."
  final String body;

  final NotificationCategory category;

  /// The rule that produced this notification, when applicable.
  final String? ruleId;

  final DateTime createdAt;
  final bool delivered;
  final bool read;

  @override
  String toString() => 'AppNotification($id, "$title")';
}
