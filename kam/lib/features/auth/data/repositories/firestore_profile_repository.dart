import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/firebase/firebase_error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../location/domain/models/location_state.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/repositories/profile_repository.dart';

/// [ProfileRepository] backed by the documents defined in
/// `docs/architecture/FIRESTORE_DATA_MODEL.md` §2:
///
/// ```text
/// users/{uid}                        displayName, photoUrl, timeZone, timestamps
/// users/{uid}/settings/preferences   notificationPreference, homeLocation
/// ```
///
/// Notes:
///
/// - `createdAt` / `updatedAt` are written with `FieldValue.serverTimestamp()`,
///   because the Security Rules require them to equal `request.time`. A client
///   cannot backdate its own profile (FIRESTORE_DATA_MODEL §7).
/// - [createProfile] is idempotent inside a transaction, so a retried
///   registration cannot overwrite a profile the user has since edited.
/// - The partner never reads these documents; `SettingsRule` and the pair rules
///   in `firebase/firestore.rules` enforce owner-only access, and the partner sees
///   only the denormalised `pairs/{pairId}/members/{uid}` name.
class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository(this._firestore, this._logger);

  final FirebaseFirestore _firestore;
  final AppLogger _logger;

  DocumentReference<Map<String, dynamic>> _profile(String uid) =>
      _firestore.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _preferences(String uid) =>
      _profile(uid).collection('settings').doc('preferences');

  @override
  Future<Result<AppUser?>> getProfile(String uid) async {
    try {
      final snapshot = await _profile(uid).get();
      if (!snapshot.exists) {
        // The document genuinely does not exist. Never synthesise a profile.
        return const Success<AppUser?>(null);
      }
      final data = snapshot.data();
      final displayName = _readDisplayName(data);
      if (displayName == null) {
        // Malformed document: report it instead of inventing a name (FR-048).
        return const Failure<AppUser?>(_incompleteProfile);
      }
      return Success<AppUser?>(_toAppUser(uid, data!, displayName));
    } catch (error, stackTrace) {
      return Failure<AppUser?>(_classify('getProfile', error, stackTrace));
    }
  }

  @override
  Stream<Result<AppUser?>> watchProfile(String uid) async* {
    try {
      await for (final snapshot in _profile(uid).snapshots()) {
        final data = snapshot.data();
        final displayName = _readDisplayName(data);
        if (!snapshot.exists) {
          yield const Success<AppUser?>(null);
        } else if (displayName == null) {
          yield const Failure<AppUser?>(_incompleteProfile);
        } else {
          yield Success<AppUser?>(_toAppUser(uid, data!, displayName));
        }
      }
    } catch (error, stackTrace) {
      yield Failure<AppUser?>(_classify('watchProfile', error, stackTrace));
    }
  }

  @override
  Future<Result<AppUser>> createProfile({
    required String uid,
    required String displayName,
    String? timeZone,
  }) async {
    try {
      await _firestore.runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(_profile(uid));
        if (snapshot.exists) {
          // Idempotent: keep what the user already has.
          return;
        }
        // Null-aware map entries: an absent optional field is omitted rather
        // than written as an explicit null.
        transaction.set(_profile(uid), <String, dynamic>{
          'displayName': displayName,
          'timeZone': ?timeZone,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (error, stackTrace) {
      return Failure<AppUser>(_classify('createProfile', error, stackTrace));
    }

    // The transaction cannot return server-resolved timestamps, so the stored
    // document is read back. One extra read on registration only.
    return _readBack('createProfile', uid);
  }

  @override
  Future<Result<AppUser>> updateProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
    String? timeZone,
  }) async {
    try {
      // `update` (not `set`) deliberately: it fails when no profile exists, so an
      // update can never silently create a document the app did not expect.
      await _profile(uid).update(<String, dynamic>{
        'displayName': ?displayName,
        'photoUrl': ?photoUrl,
        'timeZone': ?timeZone,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      return Failure<AppUser>(_classify('updateProfile', error, stackTrace));
    }

    // Keep the minimal, partner-approved profile copy current in existing
    // pair records. A failure here must not turn a successful private profile
    // update into an apparent failure; the dashboard can still use its generic
    // partner label until the copy is available.
    try {
      await _syncPairMemberProfiles(
        uid,
        displayName: displayName,
        photoUrl: photoUrl,
      );
    } on FirebaseException {
      _logger.warning(
        'Partner-visible profile refresh failed',
        context: {'operation': 'syncPairMemberProfiles'},
      );
    }

    return _readBack('updateProfile', uid);
  }

  Future<void> _syncPairMemberProfiles(
    String uid, {
    String? displayName,
    String? photoUrl,
  }) async {
    final pairs = await _firestore
        .collection('pairs')
        .where('memberIds', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .get();
    final existingProfile = await _profile(uid).get();
    final storedName = existingProfile.data()?['displayName'];
    final name = displayName ?? (storedName is String ? storedName : null);
    final update = <String, Object?>{
      'displayName': ?name,
      'photoUrl': ?photoUrl,
    };
    if (update.isEmpty) return;
    await Future.wait(
      pairs.docs.map(
        (pair) => pair.reference
            .collection('members')
            .doc(uid)
            .set(update, SetOptions(merge: true)),
      ),
    );
  }

  @override
  Future<Result<UserPreferences>> getPreferences(String uid) async {
    try {
      final snapshot = await _preferences(uid).get();
      if (!snapshot.exists) {
        return const Success<UserPreferences>(UserPreferences.defaults);
      }
      return Success<UserPreferences>(
        _toPreferences(snapshot.data() ?? const {}),
      );
    } catch (error, stackTrace) {
      return Failure<UserPreferences>(
        _classify('getPreferences', error, stackTrace),
      );
    }
  }

  @override
  Future<Result<UserPreferences>> updatePreferences({
    required String uid,
    NotificationPreference? notificationPreference,
    HomeLocationOverride homeLocation = const HomeLocationOverride.unchanged(),
  }) async {
    try {
      await _preferences(uid).set(<String, dynamic>{
        'notificationPreference': ?notificationPreference?.name,
        if (homeLocation.isCleared) 'homeLocation': FieldValue.delete(),
        if (homeLocation.value != null)
          'homeLocation': _toHomeLocationMap(homeLocation.value!),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      return Failure<UserPreferences>(
        _classify('updatePreferences', error, stackTrace),
      );
    }

    return getPreferences(uid);
  }

  /// Reads the profile back so the returned model carries real timestamps.
  Future<Result<AppUser>> _readBack(String operation, String uid) async {
    final result = await getProfile(uid);
    return result.fold(
      onSuccess: (profile) => profile == null
          ? Failure<AppUser>(
              ValidationFailure(
                'Your profile could not be read back after saving. '
                'Please try again.',
              ),
            )
          : Success<AppUser>(profile),
      onFailure: (failure) => Failure<AppUser>(failure),
    );
  }

  AppFailure _classify(String operation, Object error, StackTrace stackTrace) {
    final failure = FirebaseErrorMapper.toFailure(error, stackTrace);
    // Only non-identifying metadata is logged: a uid or profile body must not
    // end up in logs (NFR-045).
    _logger.warning(
      'Profile operation failed',
      context: {'operation': operation, 'failureType': failure.type.name},
    );
    return failure;
  }

  static const ValidationFailure _incompleteProfile = ValidationFailure(
    'Your profile is incomplete. Please set your display name again.',
  );

  static String? _readDisplayName(Map<String, dynamic>? data) {
    final value = data?['displayName'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static AppUser _toAppUser(
    String uid,
    Map<String, dynamic> data,
    String displayName,
  ) {
    return AppUser(
      id: uid,
      displayName: displayName,
      photoUrl: data['photoUrl'] as String?,
      timeZone: data['timeZone'] as String?,
      createdAt: _asUtcDateTime(data['createdAt']),
      updatedAt: _asUtcDateTime(data['updatedAt']),
    );
  }

  static UserPreferences _toPreferences(Map<String, dynamic> data) {
    return UserPreferences(
      notificationPreference: _notificationPreference(
        data['notificationPreference'],
      ),
      homeLocation: _homeLocation(data['homeLocation']),
      updatedAt: _asUtcDateTime(data['updatedAt']),
    );
  }

  static NotificationPreference _notificationPreference(Object? raw) {
    if (raw is! String) return NotificationPreference.allRuleNotifications;
    // An unrecognised stored value falls back to the documented default rather
    // than throwing: a preference is not worth failing the whole screen for.
    return NotificationPreference.values.firstWhere(
      (preference) => preference.name == raw,
      orElse: () => NotificationPreference.allRuleNotifications,
    );
  }

  static HomeLocation? _homeLocation(Object? raw) {
    if (raw is! Map) return null;
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    if (latitude is! num || longitude is! num) return null;
    final radius = raw['radiusKm'];
    final label = raw['label'];
    return HomeLocation(
      coordinate: Coordinate(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
      label: label is String ? label : null,
      radiusKm: radius is num ? radius.toDouble() : 0.3,
      // Absent on documents written before home could be disabled: an existing
      // home stays enabled rather than silently switching off.
      enabled: raw['enabled'] != false,
    );
  }

  static Map<String, dynamic> _toHomeLocationMap(HomeLocation location) {
    return <String, dynamic>{
      'latitude': location.coordinate.latitude,
      'longitude': location.coordinate.longitude,
      if (location.label != null) 'label': location.label,
      'radiusKm': location.radiusKm,
      'enabled': location.enabled,
    };
  }

  /// Firestore timestamps are UTC instants (NFR-026, FIRESTORE_DATA_MODEL §7).
  static DateTime? _asUtcDateTime(Object? value) =>
      value is Timestamp ? value.toDate().toUtc() : null;
}
