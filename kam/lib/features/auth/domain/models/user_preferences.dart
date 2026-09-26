import '../../../location/domain/models/location_state.dart';

/// How much the user wants to be notified (SRS FR-042).
enum NotificationPreference {
  allRuleNotifications,
  importantOnly,
  noNotifications,

  /// Only rules the user explicitly marked as notifiable.
  specificRulesOnly,
}

/// Private per-user settings (SRS FR-002, FR-022, FR-042).
///
/// Stored at `users/{uid}/settings/preferences` and readable **only by the owner**
/// (`firestore.rules`). This is where the home location lives precisely so a
/// partner can never read coordinates: the partner sees only the derived
/// distance/presence values written into the pair's shared state
/// (FIRESTORE_DATA_MODEL §2, NFR-005, NFR-036).
///
/// Pure Dart. Location tracking itself belongs to the location phase; only the
/// stored configuration is modelled here.
class UserPreferences {
  const UserPreferences({
    this.notificationPreference = NotificationPreference.allRuleNotifications,
    this.homeLocation,
    this.updatedAt,
  });

  /// A user who has not configured anything yet.
  ///
  /// This is the honest default for a missing document: the declared defaults are
  /// application-level defaults, not invented observations.
  static const UserPreferences defaults = UserPreferences();

  /// How the user wishes to be notified (FR-042).
  final NotificationPreference notificationPreference;

  /// The user's configured home location (FR-022), if set.
  final HomeLocation? homeLocation;

  /// Server timestamp of the last change.
  final DateTime? updatedAt;

  /// Returns a copy with the given fields replaced.
  UserPreferences copyWith({
    NotificationPreference? notificationPreference,
    HomeLocation? homeLocation,
    bool clearHomeLocation = false,
    DateTime? updatedAt,
  }) {
    return UserPreferences(
      notificationPreference:
          notificationPreference ?? this.notificationPreference,
      homeLocation: clearHomeLocation
          ? null
          : (homeLocation ?? this.homeLocation),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'UserPreferences(notifications: ${notificationPreference.name}, '
      'homeLocation: ${homeLocation != null})';
}
