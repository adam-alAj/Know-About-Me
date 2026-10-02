import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/logging/app_logger.dart';

import '../../domain/models/remote_device_state.dart';
import '../../domain/models/sync_payload.dart';
import '../../domain/sources/device_state_sync_gateway.dart';

/// Firestore implementation of [DeviceStateSyncGateway].
///
/// It performs plain document writes at `pairs/{pairId}/deviceState/{ownerId}`
/// and `pairs/{pairId}/location/{ownerId}`. Authorization is **not** implemented
/// here: Firestore Security Rules decide, and a request they reject comes back
/// as `permission-denied`. There is no privileged server in this project
/// (ADR-009), so this client can only ever write its own document.
class FirestoreDeviceStateSyncGateway implements DeviceStateSyncGateway {
  FirestoreDeviceStateSyncGateway(
    this._db, {
    required this.now,
    this.logger = const NoopAppLogger(),
  });

  final FirebaseFirestore _db;

  /// Injected clock, used to stamp when a document was received locally.
  final DateTime Function() now;
  final AppLogger logger;

  static const String _deviceStateCollection = 'deviceState';
  static const String _locationCollection = 'location';

  @override
  Future<SyncWriteResult> publish({
    required String pairId,
    required String ownerId,
    required SyncPayload payload,
  }) async {
    final reference = _document(pairId, ownerId, payload.kind);

    // Nothing may be shared: remove the document so previously exposed data is
    // actually retracted rather than merely hidden behind a rule.
    if (!payload.shareable) {
      if (!payload.retract) {
        // The caller decided to withhold, so there is nothing to do at all.
        return const SyncWriteResult.published();
      }
      try {
        logger.info(
          'FIRESTORE_WRITE_STARTED',
          context: {
            'operation': 'delete',
            'documentKind': payload.kind.name,
            'stateVersion': payload.fields['stateVersion'],
          },
        );
        await reference.delete();
        logger.info(
          'FIRESTORE_WRITE_SUCCESS',
          context: {
            'operation': 'delete',
            'documentKind': payload.kind.name,
            'stateVersion': payload.fields['stateVersion'],
          },
        );
        return const SyncWriteResult.deleted();
      } on FirebaseException catch (error) {
        logger.warning(
          'FIRESTORE_WRITE_FAILED',
          context: {
            'operation': 'delete',
            'documentKind': payload.kind.name,
            'errorCode': error.code,
          },
        );
        return SyncWriteResult.failed(_safeCode(error));
      }
    }

    try {
      logger.info(
        'FIRESTORE_WRITE_STARTED',
        context: {
          'operation': 'set',
          'documentKind': payload.kind.name,
          'stateVersion': payload.fields['stateVersion'],
        },
      );
      final data = <String, Object?>{
        for (final entry in payload.fields.entries)
          entry.key: _toFirestoreValue(entry.value),
      };
      // Fields whose category was just switched off are removed in the same
      // write, so the partner never keeps seeing a value that is no longer
      // shared even briefly.
      for (final field in payload.clearedFields) {
        data[field] = FieldValue.delete();
      }
      // Synchronization metadata: the server's clock, never the device's, and
      // never a substitute for `observedAt`.
      data['updatedAt'] = FieldValue.serverTimestamp();

      await reference.set(data, SetOptions(merge: true));
      logger.info(
        'FIRESTORE_WRITE_SUCCESS',
        context: {
          'operation': 'set',
          'documentKind': payload.kind.name,
          'stateVersion': payload.fields['stateVersion'],
        },
      );
      return const SyncWriteResult.published();
    } on FirebaseException catch (error) {
      logger.warning(
        'FIRESTORE_WRITE_FAILED',
        context: {
          'operation': 'set',
          'documentKind': payload.kind.name,
          'errorCode': error.code,
        },
      );
      return SyncWriteResult.failed(_safeCode(error));
    }
  }

  @override
  Stream<RemoteStateDocument> watch({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  }) {
    // Metadata changes are requested explicitly. Without this, Firestore only
    // re-emits when the *document data* changes: a cache-served snapshot whose
    // server-confirmed twin is byte-identical never produces a second event, so
    // `isFromCache` would stay `true` for the whole session. That is exactly
    // what made a fully-online device keep reporting “Offline — showing last
    // known data” (Phase 20 §9, §23).
    logger.debug(
      'FIRESTORE_LISTENER_ATTACHED',
      context: {'documentKind': kind.name},
    );
    return _document(pairId, ownerId, kind)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final data = snapshot.data();
          logger.debug(
            snapshot.metadata.isFromCache
                ? 'FIRESTORE_SNAPSHOT_FROM_CACHE'
                : 'FIRESTORE_SNAPSHOT_FROM_SERVER',
            context: {
              'documentKind': kind.name,
              'hasPendingWrites': snapshot.metadata.hasPendingWrites,
              'exists': snapshot.exists,
            },
          );
          return RemoteStateDocument(
            data: data == null ? const <String, Object?>{} : _toDartMap(data),
            receivedAt: now().toUtc(),
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          );
        })
        .handleError((Object error, StackTrace stackTrace) {
          logger.warning(
            'FIRESTORE_LISTENER_ERROR',
            context: {
              'documentKind': kind.name,
              'errorType': error.runtimeType.toString(),
            },
          );
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  @override
  Future<RemoteStateDocument> readFromServer({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  }) async {
    final snapshot = await _document(
      pairId,
      ownerId,
      kind,
    ).get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    return RemoteStateDocument(
      data: data == null ? const <String, Object?>{} : _toDartMap(data),
      receivedAt: now().toUtc(),
      isFromCache: snapshot.metadata.isFromCache,
      hasPendingWrites: snapshot.metadata.hasPendingWrites,
    );
  }

  DocumentReference<Map<String, dynamic>> _document(
    String pairId,
    String ownerId,
    SyncDocumentKind kind,
  ) {
    final collection = kind == SyncDocumentKind.location
        ? _locationCollection
        : _deviceStateCollection;
    return _db
        .collection('pairs')
        .doc(pairId)
        .collection(collection)
        .doc(ownerId);
  }

  /// Only the Firestore error *code* is retained: a message could echo a value
  /// back, and coordinates must never reach a log or an exception message
  /// (Phase 11 §37, NFR-045).
  static String _safeCode(FirebaseException error) => error.code;

  static Object? _toFirestoreValue(Object? value) =>
      value is DateTime ? Timestamp.fromDate(value.toUtc()) : value;

  /// Converts a document into plain Dart values, so the domain parser never has
  /// to know about Firestore types.
  static Map<String, Object?> _toDartMap(Map<String, dynamic> data) => {
    for (final entry in data.entries) entry.key: _toDartValue(entry.value),
  };

  static Object? _toDartValue(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _toDartValue(entry.value),
      };
    }
    if (value is List) return value.map(_toDartValue).toList();
    return value;
  }
}
