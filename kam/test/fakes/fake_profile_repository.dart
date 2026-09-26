import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';
import 'package:kam/features/auth/domain/models/user_preferences.dart';
import 'package:kam/features/auth/domain/repositories/profile_repository.dart';

/// Test double for [ProfileRepository] (SRS Task 23).
///
/// Models the three states the app must distinguish: a profile exists, no profile
/// exists, and the read failed. Writes can be made to fail independently, which is
/// what lets a test prove the registration partial-failure path.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.profile,
    this.preferences = UserPreferences.defaults,
    this.readFailure,
    this.createFailure,
    this.updateFailure,
    this.preferencesFailure,
  });

  /// The stored profile, or `null` when none exists.
  AppUser? profile;

  /// The stored preferences.
  UserPreferences preferences;

  AppFailure? readFailure;
  AppFailure? createFailure;
  AppFailure? updateFailure;
  AppFailure? preferencesFailure;

  int createCallCount = 0;
  int updateCallCount = 0;

  @override
  Future<Result<AppUser?>> getProfile(String uid) async {
    final failure = readFailure;
    if (failure != null) return Failure<AppUser?>(failure);
    return Success<AppUser?>(profile);
  }

  @override
  Stream<Result<AppUser?>> watchProfile(String uid) =>
      Stream<Result<AppUser?>>.value(Success<AppUser?>(profile));

  @override
  Future<Result<AppUser>> createProfile({
    required String uid,
    required String displayName,
    String? timeZone,
  }) async {
    createCallCount++;
    final failure = createFailure;
    if (failure != null) return Failure<AppUser>(failure);
    // Idempotent, exactly like the Firestore implementation: an existing profile
    // is returned untouched rather than overwritten.
    final existing = profile;
    if (existing != null) return Success<AppUser>(existing);
    profile = AppUser(id: uid, displayName: displayName, timeZone: timeZone);
    return Success<AppUser>(profile!);
  }

  @override
  Future<Result<AppUser>> updateProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
    String? timeZone,
  }) async {
    updateCallCount++;
    final failure = updateFailure;
    if (failure != null) return Failure<AppUser>(failure);
    final existing = profile;
    if (existing == null) {
      return Failure<AppUser>(
        const NotFoundFailure('That information is no longer available.'),
      );
    }
    profile = existing.copyWith(
      displayName: displayName,
      photoUrl: photoUrl,
      timeZone: timeZone,
    );
    return Success<AppUser>(profile!);
  }

  @override
  Future<Result<UserPreferences>> getPreferences(String uid) async {
    final failure = preferencesFailure;
    if (failure != null) return Failure<UserPreferences>(failure);
    return Success<UserPreferences>(preferences);
  }

  @override
  Future<Result<UserPreferences>> updatePreferences({
    required String uid,
    NotificationPreference? notificationPreference,
    HomeLocationOverride homeLocation = const HomeLocationOverride.unchanged(),
  }) async {
    final failure = preferencesFailure;
    if (failure != null) return Failure<UserPreferences>(failure);
    preferences = preferences.copyWith(
      notificationPreference: notificationPreference,
      homeLocation: homeLocation.value,
      clearHomeLocation: homeLocation.isCleared,
    );
    return Success<UserPreferences>(preferences);
  }
}
