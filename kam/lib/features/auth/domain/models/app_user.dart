import '../../../location/domain/models/location_state.dart';

/// How much the user wants to be notified (SRS FR-042).
enum NotificationPreference {
  allRuleNotifications,
  importantOnly,
  noNotifications,

  /// Only rules the user explicitly marked as notifiable.
  specificRulesOnly,
}

/// A user profile (SRS FR-002).
///
/// Named [AppUser] to avoid colliding with Firebase's `User` type once the
/// authentication layer is implemented.
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.homeLocation,
    this.timeZone,
    this.notificationPreference = NotificationPreference.allRuleNotifications,
    this.createdAt,
    this.updatedAt,
  });

  /// The stable identity assigned by the authentication provider (FR-001).
  final String id;

  final String displayName;

  final String? photoUrl;

  /// The user's configured home location (FR-022).
  final HomeLocation? homeLocation;

  /// IANA time-zone name used to render timestamps locally (NFR-026).
  final String? timeZone;

  final NotificationPreference notificationPreference;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  String toString() => 'AppUser($id, $displayName)';
}
