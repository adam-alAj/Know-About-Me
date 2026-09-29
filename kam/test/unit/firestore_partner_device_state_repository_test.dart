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
  int cancelledStreams = 0;
  bool get cancelled => cancelledStreams == 2;

  @override
  Stream<RemoteStateDocument> watch({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  }) => switch (kind) {
    SyncDocumentKind.deviceState => state.stream,
    SyncDocumentKind.location => location.stream,
  };

  @override
  Future<SyncWriteResult> publish({
    required String pairId,
    required String ownerId,
    required SyncPayload payload,
  }) async => const SyncWriteResult.published();
}
