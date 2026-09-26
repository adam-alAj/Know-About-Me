import '../../../../core/result/result.dart';
import '../../../location/domain/models/location_state.dart';
import '../models/app_user.dart';
import '../models/user_preferences.dart';

/// Contract for the user's own profile documents (SRS FR-002).
///
/// Backed by Firestore in `FirestoreProfileRepository`, which writes exactly the
/// `users/{uid}` and `users/{uid}/settings/preferences` shapes defined in
/// `docs/architecture/FIRESTORE_DATA_MODEL.md` §2. No other feature may read or
/// write those documents, and the UI never touches Firestore (constraint 4).
///
/// "No profile yet" is reported as `null` inside a [Success], never as a
/// fabricated [AppUser]: the SRS forbids inventing state the system cannot
/// substantiate (FR-048, NFR-006).
abstract interface class ProfileRepository {
  /// Reads `users/{uid}`, or `null` when the document does not exist.
  Future<Result<AppUser?>> getProfile(String uid);

  /// Streams `users/{uid}` so a profile edit on another device is reflected.
  ///
  /// Emits `null` while the document is absent.
  Stream<Result<AppUser?>> watchProfile(String uid);

  /// Creates `users/{uid}` and returns the stored profile.
  ///
  /// Must be **idempotent**: if the document already exists the existing profile
  /// is returned unchanged. Registration can therefore be retried after a partial
  /// failure without creating a second profile or overwriting user edits
  /// (SRS Task 5).
  ///
  /// Only the caller's own uid may be used; the Security Rules reject anything
  /// else, and [uid] must therefore come from the authentication provider.
  Future<Result<AppUser>> createProfile({
    required String uid,
    required String displayName,
    String? timeZone,
  });

  /// Updates the user-editable profile fields.
  ///
  /// [uid] and `createdAt` are not parameters: ownership and creation time cannot
  /// be expressed as a change (SRS Task 15).
  Future<Result<AppUser>> updateProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
    String? timeZone,
  });

  /// Reads `users/{uid}/settings/preferences`.
  ///
  /// A missing document is reported as [UserPreferences.defaults], because the
  /// application defined those defaults; the document itself is not invented.
  Future<Result<UserPreferences>> getPreferences(String uid);

  /// Writes `users/{uid}/settings/preferences`.
  Future<Result<UserPreferences>> updatePreferences({
    required String uid,
    NotificationPreference? notificationPreference,
    HomeLocationOverride homeLocation = const HomeLocationOverride.unchanged(),
  });
}

/// Explicit tri-state for the optional home location on a preferences update.
///
/// A nullable `HomeLocation?` parameter could not distinguish "leave unchanged"
/// from "clear", and silently clearing a user's home location would be a data
/// loss bug (FR-022).
class HomeLocationOverride {
  /// Leave the stored value untouched.
  const HomeLocationOverride.unchanged() : value = null, isCleared = false;

  /// Store a new value.
  const HomeLocationOverride.set(HomeLocation location)
    : value = location,
      isCleared = false;

  /// Remove any stored value.
  const HomeLocationOverride.cleared() : value = null, isCleared = true;

  /// The new value, when [isCleared] is false and a value was supplied.
  final HomeLocation? value;

  /// Whether the stored value should be removed.
  final bool isCleared;
}
