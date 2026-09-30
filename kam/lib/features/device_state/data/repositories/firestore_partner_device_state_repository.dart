import 'dart:async';

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
  });

  final DeviceStateSyncGateway _gateway;
  final RemoteDeviceStateParser parser;

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

      final parsedState = stateDocument == null
          ? null
          : parser.parseDeviceState(
              pairId: pairId,
              expectedOwnerUserId: partnerUserId,
              document: stateDocument,
            );
      final parsedLocation = locationDocumentSnapshot == null
          ? RemoteLocationState.unavailable
          : parser.parseLocation(
              expectedOwnerUserId: partnerUserId,
              document: locationDocumentSnapshot,
            );

      final RemoteDeviceState? merged;
      if (parsedState != null) {
        merged = parsedState.withLocation(
          parsedLocation,
          isFromCache:
              (stateDocument?.isFromCache ?? false) ||
              (locationDocumentSnapshot?.isFromCache ?? false),
        );
      } else if (parsedLocation.hasCoordinates) {
        // The state document is absent or unreadable, but the partner did
        // publish a location. A location-only view is still truthful: it reports
        // only the facts that exist and leaves every other metric unavailable.
        merged = RemoteDeviceState.locationOnly(
          pairId: pairId,
          ownerUserId: partnerUserId,
          location: parsedLocation,
          schemaVersion: 1,
          receivedAt: locationDocumentSnapshot!.receivedAt,
          isFromCache: locationDocumentSnapshot.isFromCache,
          deviceId: _string(locationDocumentSnapshot.data['deviceId']),
          stateVersion: _int(locationDocumentSnapshot.data['stateVersion']),
        );
      } else {
        // Nothing recognizable has ever been published. Emitting an empty state
        // would be inventing one.
        merged = null;
      }

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
            .listen(
              (document) {
                deviceStateDocument = document;
                deviceStateReady = true;
                maybeEmit();
              },
              onError: controller.addError,
            ),
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
            .listen(
              (document) {
                locationDocument = document;
                locationReady = true;
                maybeEmit();
              },
              onError: controller.addError,
            ),
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
}
