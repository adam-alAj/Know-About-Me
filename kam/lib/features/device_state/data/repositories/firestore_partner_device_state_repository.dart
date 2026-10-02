import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../domain/models/remote_device_state.dart';
import '../../domain/models/sync_payload.dart';
import '../../domain/repositories/partner_device_state_repository.dart';
import '../../domain/services/remote_device_state_parser.dart';
import '../../domain/sources/device_state_sync_gateway.dart';

/// Reads the authorized partner's synchronized documents.
///
/// Two documents exist (state and location), but only the ones the partner
/// actually shares are watched. Each document has its own read gate in the
/// security rules, and reading one whose category is not shared comes back as a
/// `permission-denied` error. Subscribing blindly would therefore let a
/// document the partner has *not* shared take down the state they *have*
/// shared. The caller passes what the partner shares, and an unwatched document
/// is reported as explicitly unavailable rather than fetched and denied.
///
/// The repository:
///
/// * never subscribes to a pair the caller did not resolve from authenticated
///   application state;
/// * waits for every watched document's first value before emitting, so the UI
///   never shows a location-less state and then silently corrects itself;
/// * cancels every subscription when the listener is cancelled, so a pair
///   change, a revocation or a sign-out cannot leak a listener (Phase 11 §21);
/// * reports cache-served values as [RemoteDeviceState.isFromCache] rather than
///   as current state (Phase 11 §31, §32).
class FirestorePartnerDeviceStateRepository
    implements PartnerDeviceStateRepository {
  FirestorePartnerDeviceStateRepository(
    this._gateway, {
    this.parser = const RemoteDeviceStateParser(),
    this.logger = const NoopAppLogger(),
  });

  final DeviceStateSyncGateway _gateway;
  final RemoteDeviceStateParser parser;
  final AppLogger logger;
  final Map<String, int> _latestServerVersions = <String, int>{};

  @override
  Future<PartnerDeviceState?> readFromServer({
    required String pairId,
    required String partnerUserId,
    bool watchDeviceState = true,
    bool watchLocation = true,
  }) async {
    if (!watchDeviceState && !watchLocation) return null;
    final now = DateTime.now().toUtc();
    final documents = await Future.wait<RemoteStateDocument>([
      watchDeviceState
          ? _gateway.readFromServer(
              pairId: pairId,
              ownerId: partnerUserId,
              kind: SyncDocumentKind.deviceState,
            )
          : Future<RemoteStateDocument>.value(
              RemoteStateDocument.absent(receivedAt: now),
            ),
      watchLocation
          ? _gateway.readFromServer(
              pairId: pairId,
              ownerId: partnerUserId,
              kind: SyncDocumentKind.location,
            )
          : Future<RemoteStateDocument>.value(
              RemoteStateDocument.absent(receivedAt: now),
            ),
    ]);
    final merged = _mergeDocuments(
      pairId: pairId,
      partnerUserId: partnerUserId,
      stateDocument: watchDeviceState ? documents[0] : null,
      locationDocument: watchLocation ? documents[1] : null,
      parser: parser,
    );
    final state = merged;
    final version = state?.stateVersion;
    final key = '$pairId/$partnerUserId';
    final previous = _latestServerVersions[key];
    if (version != null && previous != null && version < previous) {
      logger.warning(
        'STALE_STATE_REJECTED',
        context: {
          'incomingVersion': version,
          'currentVersion': previous,
          'source': 'server_read',
        },
      );
      throw StateVersionRegressionException();
    }
    if (version != null) _latestServerVersions[key] = version;
    return state == null ? null : PartnerDeviceState(state);
  }

  @override
  Stream<PartnerDeviceState?> watch({
    required String pairId,
    required String partnerUserId,
    bool watchDeviceState = true,
    bool watchLocation = true,
  }) {
    final controller = StreamController<PartnerDeviceState?>();
    final subscriptions = <StreamSubscription<RemoteStateDocument>>[];

    RemoteStateDocument? deviceStateDocument;
    RemoteStateDocument? locationDocument;
    final versionKey = '$pairId/$partnerUserId';
    // A document we deliberately do not watch is already settled: it is
    // unavailable, not still pending.
    var deviceStateReady = !watchDeviceState;
    var locationReady = !watchLocation;
    var cancelled = false;

    void emit() {
      if (cancelled || controller.isClosed) return;
      if (!deviceStateReady || !locationReady) return;

      final stateDocument = deviceStateDocument;
      final locationDocumentSnapshot = locationDocument;

      final merged = _mergeDocuments(
        pairId: pairId,
        partnerUserId: partnerUserId,
        stateDocument: stateDocument,
        locationDocument: locationDocumentSnapshot,
        parser: parser,
      );
      final version = merged?.stateVersion;
      final highest = _latestServerVersions[versionKey];
      if (version != null && highest != null && version < highest) {
        logger.warning(
          'STALE_STATE_REJECTED',
          context: {
            'incomingVersion': version,
            'currentVersion': highest,
            'source': merged!.isFromCache ? 'cache' : 'server',
          },
        );
        return;
      }
      if (version != null && merged != null && !merged.isFromCache) {
        _latestServerVersions[versionKey] = version;
      }
      logger.debug(
        'REMOTE_STATE_PARSED',
        context: {
          'stateVersion': version,
          'isFromCache':
              merged?.isFromCache ??
              ((stateDocument?.isFromCache ?? false) ||
                  (locationDocumentSnapshot?.isFromCache ?? false)),
          'hasPendingWrites':
              merged?.hasPendingWrites ??
              ((stateDocument?.hasPendingWrites ?? false) ||
                  (locationDocumentSnapshot?.hasPendingWrites ?? false)),
          'hasState': merged != null,
        },
      );
      controller.add(merged == null ? null : PartnerDeviceState(merged));
    }

    void maybeEmit() {
      if (!deviceStateReady || !locationReady) return;
      emit();
    }

    if (watchDeviceState) {
      subscriptions.add(
        _gateway
            .watch(
              pairId: pairId,
              ownerId: partnerUserId,
              kind: SyncDocumentKind.deviceState,
            )
            .listen((document) {
              deviceStateDocument = document;
              deviceStateReady = true;
              maybeEmit();
            }, onError: controller.addError),
      );
    }

    if (watchLocation) {
      subscriptions.add(
        _gateway
            .watch(
              pairId: pairId,
              ownerId: partnerUserId,
              kind: SyncDocumentKind.location,
            )
            .listen((document) {
              locationDocument = document;
              locationReady = true;
              maybeEmit();
            }, onError: controller.addError),
      );
    }

    // Nothing is watched (for example the partner currently shares no
    // device-state or location category). Answer definitively instead of
    // holding a value that can never arrive.
    if (!watchDeviceState && !watchLocation) emit();

    controller.onCancel = () async {
      cancelled = true;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };

    return controller.stream;
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int? _int(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : null;

  static RemoteDeviceState? _mergeDocuments({
    required String pairId,
    required String partnerUserId,
    required RemoteStateDocument? stateDocument,
    required RemoteStateDocument? locationDocument,
    required RemoteDeviceStateParser parser,
  }) {
    final parsedState = stateDocument == null
        ? null
        : parser.parseDeviceState(
            pairId: pairId,
            expectedOwnerUserId: partnerUserId,
            document: stateDocument,
          );
    final parsedLocation = locationDocument == null
        ? RemoteLocationState.unavailable
        : parser.parseLocation(
            expectedOwnerUserId: partnerUserId,
            document: locationDocument,
          );
    final cached =
        (stateDocument?.isFromCache ?? false) ||
        (locationDocument?.isFromCache ?? false);
    final pending =
        (stateDocument?.hasPendingWrites ?? false) ||
        (locationDocument?.hasPendingWrites ?? false);

    if (parsedState != null) {
      return parsedState.withLocation(
        parsedLocation,
        isFromCache: cached,
        hasPendingWrites: pending,
      );
    }
    if (parsedLocation.hasCoordinates && locationDocument != null) {
      return RemoteDeviceState.locationOnly(
        pairId: pairId,
        ownerUserId: partnerUserId,
        location: parsedLocation,
        schemaVersion: 1,
        receivedAt: locationDocument.receivedAt,
        isFromCache: cached,
        hasPendingWrites: pending,
        deviceId: _string(locationDocument.data['deviceId']),
        stateVersion: _int(locationDocument.data['stateVersion']),
      );
    }
    return null;
  }
}

/// The server returned a state older than one already confirmed in this
/// repository session. Callers should keep the newer value and report refresh
/// failure rather than interpreting the regression as deletion.
class StateVersionRegressionException implements Exception {
  const StateVersionRegressionException();
}
