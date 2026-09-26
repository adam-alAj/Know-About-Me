import '../../../../core/error/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/repositories/profile_repository.dart';

/// [ProfileRepository] used when this build has no reachable backend.
///
/// Chosen by `profileRepositoryProvider` when Firebase is not configured. A read
/// reports the truth — no profile — while every write fails with a
/// [ConfigurationFailure], so the app can never claim to have saved something it
/// did not (SRS constraint 10).
class UnavailableProfileRepository implements ProfileRepository {
  const UnavailableProfileRepository({this.reason = _defaultReason});

  static const String _defaultReason =
      'Profiles are unavailable in this build because no account service is '
      'configured.';

  /// User-safe explanation.
  final String reason;

  @override
  Future<Result<AppUser?>> getProfile(String uid) async =>
      const Success<AppUser?>(null);

  @override
  Stream<Result<AppUser?>> watchProfile(String uid) =>
      Stream<Result<AppUser?>>.value(const Success<AppUser?>(null));

  @override
  Future<Result<AppUser>> createProfile({
    required String uid,
    required String displayName,
    String? timeZone,
  }) async => Failure<AppUser>(ConfigurationFailure(reason));

  @override
  Future<Result<AppUser>> updateProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
    String? timeZone,
  }) async => Failure<AppUser>(ConfigurationFailure(reason));

  @override
  Future<Result<UserPreferences>> getPreferences(String uid) async =>
      const Success<UserPreferences>(UserPreferences.defaults);

  @override
  Future<Result<UserPreferences>> updatePreferences({
    required String uid,
    NotificationPreference? notificationPreference,
    HomeLocationOverride homeLocation = const HomeLocationOverride.unchanged(),
  }) async => Failure<UserPreferences>(ConfigurationFailure(reason));
}
