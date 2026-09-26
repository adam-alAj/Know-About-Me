import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../../location/domain/models/location_state.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/validation/auth_input_validation.dart';
import 'auth_providers.dart';

/// Progress of a profile write (SRS Task 17).
///
/// The *reading* states come from `currentUserProfileProvider`
/// (`AsyncValue<Result<AppUser?>>`), which is what makes "loading", "loaded",
/// "missing" and "unavailable" distinguishable. This type covers the  *writing*
/// half only, so a save cannot be mistaken for a load:
///
/// ```text
/// brief state   source
/// ────────────  ────────────────────────────────────────────────
/// Initial       this: ProfileIdle
/// Loading       currentUserProfileProvider (AsyncLoading)
/// Loaded        currentUserProfileProvider: Success(profile)
/// Updated       this: ProfileSaved
/// Error         this: ProfileSaveFailed / currentUserProfileProvider failure
/// Unavailable   currentUserProfileProvider: failure with a classified reason
/// ```
sealed class ProfileMutationState {
  const ProfileMutationState();
}

/// Nothing in flight.
final class ProfileIdle extends ProfileMutationState {
  const ProfileIdle();
}

/// A write is in flight.
final class ProfileSaving extends ProfileMutationState {
  const ProfileSaving();
}

/// The last write succeeded; the profile providers have been invalidated so the
/// UI reloads from the source of truth.
final class ProfileSaved extends ProfileMutationState {
  const ProfileSaved();
}

/// The last write failed with a classified, user-safe reason.
final class ProfileSaveFailed extends ProfileMutationState {
  const ProfileSaveFailed(this.failure);

  final AppFailure failure;
}

/// Writes the user's own profile and private settings (SRS FR-002, Task 15).
///
/// Only user-editable values are exposed. Ownership (`id`) and `createdAt` cannot
/// be expressed here at all, matching `ProfileRepository.updateProfile` and the
/// Security Rules (SRS Task 15, Task 16).
class ProfileController extends Notifier<ProfileMutationState> {
  @override
  ProfileMutationState build() => const ProfileIdle();

  /// Creates the profile when it does not exist yet, or updates the display name.
  ///
  /// Handles the recovery path for a registration whose profile write failed: the
  /// app has an identity but no document, so this creates it. Creation is
  /// idempotent, which makes the guess between create and update harmless.
  Future<Result<AppUser>> saveDisplayName(String displayName) async {
    final identity = ref.read(currentIdentityProvider);
    if (identity == null) {
      const failure = AuthenticationFailure(
        'Your session has ended. Please sign in again.',
      );
      state = ProfileSaveFailed(failure);
      return Failure<AppUser>(failure);
    }

    final invalid = AuthInputValidation.displayName(displayName);
    if (invalid != null) {
      final failure = ValidationFailure(invalid);
      state = ProfileSaveFailed(failure);
      return Failure<AppUser>(failure);
    }

    state = const ProfileSaving();
    final trimmed = displayName.trim();
    final repository = ref.read(profileRepositoryProvider);

    final result = _hasProfile
        ? await repository.updateProfile(
            uid: identity.uid,
            displayName: trimmed,
          )
        : await repository.createProfile(
            uid: identity.uid,
            displayName: trimmed,
          );

    return result.fold(
      onSuccess: (profile) {
        _refresh(identity.uid);
        return Success<AppUser>(profile);
      },
      onFailure: (failure) {
        state = ProfileSaveFailed(failure);
        return Failure<AppUser>(failure);
      },
    );
  }

  /// Stores the notification preference (SRS FR-042).
  Future<Result<UserPreferences>> setNotificationPreference(
    NotificationPreference preference,
  ) async {
    final identity = ref.read(currentIdentityProvider);
    if (identity == null) {
      const failure = AuthenticationFailure(
        'Your session has ended. Please sign in again.',
      );
      state = ProfileSaveFailed(failure);
      return Failure<UserPreferences>(failure);
    }

    state = const ProfileSaving();
    final result = await ref
        .read(profileRepositoryProvider)
        .updatePreferences(
          uid: identity.uid,
          notificationPreference: preference,
        );

    return result.fold(
      onSuccess: (preferences) {
        _refresh(identity.uid);
        return Success<UserPreferences>(preferences);
      },
      onFailure: (failure) {
        state = ProfileSaveFailed(failure);
        return Failure<UserPreferences>(failure);
      },
    );
  }

  /// Stores or clears the home location (SRS FR-022).
  ///
  /// Private to the owner: the partner only ever sees derived distance/presence
  /// values written into the pair's shared state (FIRESTORE_DATA_MODEL §2).
  Future<Result<UserPreferences>> setHomeLocation(HomeLocation? home) async {
    final identity = ref.read(currentIdentityProvider);
    if (identity == null) {
      const failure = AuthenticationFailure(
        'Your session has ended. Please sign in again.',
      );
      state = ProfileSaveFailed(failure);
      return Failure<UserPreferences>(failure);
    }

    state = const ProfileSaving();
    final result = await ref
        .read(profileRepositoryProvider)
        .updatePreferences(
          uid: identity.uid,
          homeLocation: home == null
              ? const HomeLocationOverride.cleared()
              : HomeLocationOverride.set(home),
        );

    return result.fold(
      onSuccess: (preferences) {
        _refresh(identity.uid);
        return Success<UserPreferences>(preferences);
      },
      onFailure: (failure) {
        state = ProfileSaveFailed(failure);
        return Failure<UserPreferences>(failure);
      },
    );
  }

  /// Whether a profile document is currently known to exist.
  bool get _hasProfile {
    final cached = ref.read(currentUserProfileProvider);
    if (!cached.hasValue) return false;
    return cached.requireValue.valueOrNull != null;
  }

  /// Reloads the affected providers so the UI shows stored values, not the
  /// values that were submitted.
  void _refresh(String uid) {
    ref.invalidate(userProfileProvider(uid));
    ref.invalidate(userPreferencesProvider(uid));
    state = const ProfileSaved();
  }
}

/// The [ProfileController] instance (SRS FR-002).
final profileControllerProvider =
    NotifierProvider<ProfileController, ProfileMutationState>(
      ProfileController.new,
    );
