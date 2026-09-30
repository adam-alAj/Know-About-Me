import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/data/repositories/firestore_partner_device_state_repository.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/sync_payload.dart';
import 'package:kam/features/device_state/domain/sources/device_state_sync_gateway.dart';

void main() {
  test('merged state is cache-served if either document is cached', () async {
    final gateway = _RecordingGateway();
    final repository = FirestorePartnerDeviceStateRepository(gateway);
    final receivedAt = DateTime.utc(2026, 9, 28);
    final result = repository
        .watch(pairId: 'pair-a', partnerUserId: 'user-b')
        .first;

    gateway.state.add(
      RemoteStateDocument(
        data: <String, Object?>{
          'ownerUserId': 'user-b',
          'schemaVersion': 1,
          'observedAt': receivedAt,
          'batteryPercentage': 72,
        },
        receivedAt: receivedAt,
        isFromCache: false,
      ),
    );
    gateway.location.add(
      RemoteStateDocument.absent(receivedAt: receivedAt, isFromCache: true),
    );

    final partner = await result;
    expect(partner?.state.isFromCache, isTrue);
    await gateway.state.close();
    await gateway.location.close();
  });

  test('does not read a document the partner does not share', () async {
    final gateway = _RecordingGateway();
    final repository = FirestorePartnerDeviceStateRepository(gateway);
    final receivedAt = DateTime.utc(2026, 9, 28);

    // The partner shares battery but not location, so the location read would
    // be denied by the rules. It must not be attempted at all.
    final result = repository
        .watch(
          pairId: 'pair-a',
          partnerUserId: 'user-b',
          watchLocation: false,
        )
        .first;

    gateway.state.add(
      RemoteStateDocument(
        data: <String, Object?>{
          'ownerUserId': 'user-b',
          'schemaVersion': 1,
          'observedAt': receivedAt,
          'batteryPercentage': 72,
        },
        receivedAt: receivedAt,
        isFromCache: false,
      ),
    );

    final partner = await result;
    expect(gateway.watchedKinds, isNot(contains(SyncDocumentKind.location)));
    expect(partner?.state.batteryPercentage, 72);
    expect(partner?.state.location?.hasCoordinates, isFalse);
    // Only the state document was listened to; the location controller was
    // never subscribed, so it is not closed here (its `done` future would never
    // complete).
    await gateway.state.close();
  });

  test('emits a location-only view when only location is shared', () async {
    final gateway = _RecordingGateway();
    final repository = FirestorePartnerDeviceStateRepository(gateway);
    final receivedAt = DateTime.utc(2026, 9, 28);

    // The partner shares location but no device-state category, so the state
    // document read would be denied. The location must still be shown.
    final result = repository
        .watch(
          pairId: 'pair-a',
          partnerUserId: 'user-b',
          watchDeviceState: false,
        )
        .first;

    gateway.location.add(
      RemoteStateDocument(
        data: <String, Object?>{
          'ownerUserId': 'user-b',
          'schemaVersion': 1,
          'observedAt': receivedAt,
          'latitude': 52.51,
          'longitude': 13.41,
        },
        receivedAt: receivedAt,
        isFromCache: false,
      ),
    );

    final partner = await result;
    expect(
      gateway.watchedKinds,
      isNot(contains(SyncDocumentKind.deviceState)),
    );
    expect(partner?.state.observations, isEmpty);
    expect(partner?.state.location?.hasCoordinates, isTrue);
    await gateway.location.close();
  });

  test('emits no-state without reading anything when nothing is shared', () async {
    final gateway = _RecordingGateway();
    final repository = FirestorePartnerDeviceStateRepository(gateway);

    final result = repository
        .watch(
          pairId: 'pair-a',
          partnerUserId: 'user-b',
          watchDeviceState: false,
          watchLocation: false,
        )
        .first;

    // Nothing is watched at all, so no document is read and no controller needs
    // to be closed here.
    expect(await result, isNull);
    expect(gateway.watchedKinds, isEmpty);
  });

  test('emits explicit no-state after both initial documents are absent', () async {
    final gateway = _RecordingGateway();
    final repository = FirestorePartnerDeviceStateRepository(gateway);
    final result = repository
        .watch(pairId: 'pair-a', partnerUserId: 'user-b')
        .first;
    final receivedAt = DateTime.utc(2026, 9, 28);

    gateway.state.add(
      RemoteStateDocument.absent(receivedAt: receivedAt),
    );
    gateway.location.add(
      RemoteStateDocument.absent(receivedAt: receivedAt),
    );

    expect(await result, isNull);
    expect(gateway.cancelled, isTrue);
    await gateway.state.close();
    await gateway.location.close();
  });
}

class _RecordingGateway implements DeviceStateSyncGateway {
  _RecordingGateway() {
    state.onCancel = () => cancelledStreams++;
    location.onCancel = () => cancelledStreams++;
  }

  final StreamController<RemoteStateDocument> state =
      StreamController<RemoteStateDocument>();
  final StreamController<RemoteStateDocument> location =
      StreamController<RemoteStateDocument>();
  final List<SyncDocumentKind> watchedKinds = <SyncDocumentKind>[];
  int cancelledStreams = 0;
  bool get cancelled => cancelledStreams == 2;

  @override
  Stream<RemoteStateDocument> watch({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  }) {
    watchedKinds.add(kind);
    return switch (kind) {
      SyncDocumentKind.deviceState => state.stream,
      SyncDocumentKind.location => location.stream,
    };
  }

  @override
  Future<SyncWriteResult> publish({
    required String pairId,
    required String ownerId,
    required SyncPayload payload,
  }) async => const SyncWriteResult.published();
}
