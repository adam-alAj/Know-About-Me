import '../../../privacy/domain/models/sharing_category.dart';

/// Which synchronized document a payload belongs to.
///
/// Location is its own document because Firestore rules cannot grant access to
/// part of a document: sharing battery must never also expose coordinates
/// (NFR-036).
enum SyncDocumentKind { deviceState, location }

/// A sanitized, write-ready shared-state document.
///
/// Produced by the sanitizer, never by UI code, so a value that failed
/// validation simply never reaches Firestore (Phase 11 §37).
class SyncPayload {
  const SyncPayload({
    required this.kind,
    required this.fields,
    required this.observedAt,
    required this.shareable,
    this.retract = false,
    this.clearedFields = const <String>{},
  });

  /// The owner is no longer sharing this document at all.
  ///
  /// The synchronized document must be **deleted**, so previously exposed data
  /// is actually retracted instead of merely hidden behind a rule
  /// (Phase 11 §34).
  const SyncPayload.retracted({required this.kind})
    : fields = const <String, Object?>{},
      clearedFields = const <String>{},
      observedAt = null,
      shareable = false,
      retract = true;

  /// Sharing remains on, but there is nothing trustworthy to publish right now.
  ///
  /// The last published document is left untouched: a temporarily unavailable
  /// value must not delete data the partner was legitimately shown, and it must
  /// never be replaced by a fabricated one (Phase 11 §9).
  const SyncPayload.withheld({required this.kind})
    : fields = const <String, Object?>{},
      clearedFields = const <String>{},
      observedAt = null,
      shareable = false,
      retract = false;

  final SyncDocumentKind kind;

  /// Field values ready to be written. Timestamps are UTC [DateTime]s; the data
  /// layer converts them to Firestore `Timestamp`s.
  final Map<String, Object?> fields;

  /// Fields that must be **removed** from the document because their category
  /// is no longer shared.
  ///
  /// This is what makes turning a category off actually retract data rather
  /// than merely hiding it behind a rule (Phase 11 §34).
  final Set<String> clearedFields;

  /// The newest *device observation* time carried by this payload.
  final DateTime? observedAt;

  /// Whether anything may be published at all.
  final bool shareable;

  /// Whether the document must be deleted because sharing was withdrawn.
  ///
  /// Only meaningful when [shareable] is false: it separates "stop sharing"
  /// (delete) from "nothing to say right now" (leave the document alone).
  final bool retract;

  /// Keys that change on every write and therefore never participate in
  /// change detection.
  static const Set<String> volatileKeys = <String>{
    'stateVersion',
    'schemaVersion',
    'updatedAt',
  };

  /// Canonical signature of the meaningful content.
  ///
  /// Two payloads with the same signature convey the same facts to the partner,
  /// so the second one must not be written (Phase 11 §7).
  String signature() {
    final parts = <String>[];
    for (final key in fields.keys.toList()..sort()) {
      if (volatileKeys.contains(key)) continue;
      parts.add('$key=${_encode(fields[key])}');
    }
    for (final key in clearedFields.toList()..sort()) {
      parts.add('$key=<cleared>');
    }
    final state = shareable
        ? 'shared'
        : retract
        ? 'retracted'
        : 'withheld';
    return '${kind.name}|$state|${parts.join(';')}';
  }

  /// Returns this payload stamped with [version].
  ///
  /// The version is applied after the change check, so allocating a version
  /// never itself looks like a change.
  SyncPayload withVersion(int version) => SyncPayload(
    kind: kind,
    fields: <String, Object?>{...fields, 'stateVersion': version},
    clearedFields: clearedFields,
    observedAt: observedAt,
    shareable: shareable,
    retract: retract,
  );

  static String _encode(Object? value) => value is DateTime
      ? value.toUtc().toIso8601String()
      : '$value';

  /// A description that never prints a field value, because field values can
  /// contain coordinates.
  @override
  String toString() =>
      'SyncPayload(${kind.name}, shared: $shareable, retract: $retract, '
      'fields: ${fields.length}, cleared: ${clearedFields.length})';
}

/// The categories that gate each synchronized field.
///
/// Mirrors the `shares(...)` checks in `firebase/firestore.rules`; the rules
/// remain authoritative and will reject a write that disagrees with this table.
abstract final class SyncCategoryGate {
  static const Map<SyncDocumentKind, Map<String, SharingCategory>> byField = {
    SyncDocumentKind.deviceState: {
      'batteryPercentage': SharingCategory.battery,
      'isCharging': SharingCategory.charging,
      'chargingStartedAt': SharingCategory.charging,
      'chargingDurationSeconds': SharingCategory.charging,
      'networkState': SharingCategory.network,
      'screenState': SharingCategory.activityIndicators,
      'activityState': SharingCategory.activityIndicators,
      'lastActivityAt': SharingCategory.activityIndicators,
    },
    SyncDocumentKind.location: {
      'latitude': SharingCategory.location,
      'longitude': SharingCategory.location,
      'accuracyMeters': SharingCategory.location,
      'approximate': SharingCategory.location,
      'distanceFromHomeKm': SharingCategory.distanceFromHome,
      'homePresence': SharingCategory.distanceFromHome,
    },
  };

  /// Every field name the rules allow in one document, gated or not.
  ///
  /// The rules enforce this same list with `keys().hasOnly(...)`, so an
  /// unrecognised field is rejected by the server even if a modified client
  /// tries to send one.
  static const Map<SyncDocumentKind, Set<String>> allowedFields = {
    SyncDocumentKind.deviceState: <String>{
      'ownerUserId',
      'deviceId',
      'schemaVersion',
      'stateVersion',
      'observedAt',
      'updatedAt',
      'availabilityState',
      'lastOnlineAt',
      'batteryPercentage',
      'isCharging',
      'chargingStartedAt',
      'chargingDurationSeconds',
      'networkState',
      'screenState',
      'activityState',
      'lastActivityAt',
    },
    SyncDocumentKind.location: <String>{
      'ownerUserId',
      'deviceId',
      'schemaVersion',
      'stateVersion',
      'observedAt',
      'updatedAt',
      'latitude',
      'longitude',
      'accuracyMeters',
      'approximate',
      'distanceFromHomeKm',
      'homePresence',
    },
  };
}
