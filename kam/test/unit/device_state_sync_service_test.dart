import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/domain/models/battery_state.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/sync_payload.dart';
import 'package:kam/features/device_state/domain/services/device_state_sanitizer.dart';
import 'package:kam/features/device_state/domain/services/device_state_sync_service.dart';
import 'package:kam/features/device_state/domain/services/sync_scheduler.dart';
import 'package:kam/features/device_state/domain/sources/device_state_sync_gateway.dart';
import 'package:kam/features/device_state/domain/sources/sync_version_store.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';

/// Phase 20 §12–§14, §22, §27: reconnect and retry must not turn into a burst of
/// duplicate writes, and a refusal must not become an infinite retry loop.
void main() {
  final observedAt = DateTime.utc(2026, 9, 28, 10, 2);

  group('Coalescing and change detection', () {
    test(
      'a burst of local changes becomes one write of the latest state',
      () async {
        final scheduler = _ManualScheduler();
        final gateway = _RecordingGateway();
        final service = _service(gateway: gateway, scheduler: scheduler);

        for (final level in <int>[81, 80, 79, 78, 77]) {
          service.requestPublish(
            _request(_snapshot(observedAt: observedAt, battery: level)),
          );
        }

        expect(scheduler.hasPending, isTrue);
        scheduler.fire();
        await pumpEventQueue();

        final stateWrites = gateway.writes
            .where(
              (write) => write.payload.kind == SyncDocumentKind.deviceState,
            )
            .toList();
        expect(stateWrites, hasLength(1));
        expect(stateWrites.single.payload.fields['batteryPercentage'], 77);
      },
    );

    test('unchanged content never produces a second write', () async {
      final gateway = _RecordingGateway();
      final service = _service(gateway: gateway);
      final snapshot = _snapshot(observedAt: observedAt);

      final first = await service.publishNow(
        pairId: 'pair-1',
        snapshot: snapshot,
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );
      final second = await service.publishNow(
        pairId: 'pair-1',
        snapshot: snapshot,
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );

      expect(
        first
            .firstWhere(
              (outcome) => outcome.kind == SyncDocumentKind.deviceState,
            )
            .decision,
        SyncDecision.published,
      );
      expect(
        second
            .firstWhere(
              (outcome) => outcome.kind == SyncDocumentKind.deviceState,
            )
            .decision,
        SyncDecision.unchanged,
      );
      expect(
        gateway.writes.where(
          (write) => write.payload.kind == SyncDocumentKind.deviceState,
        ),
        hasLength(1),
      );
    });

    test('a changed value does produce a second write', () async {
      final gateway = _RecordingGateway();
      final service = _service(gateway: gateway);

      await service.publishNow(
        pairId: 'pair-1',
        snapshot: _snapshot(observedAt: observedAt, battery: 80),
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );
      await service.publishNow(
        pairId: 'pair-1',
        snapshot: _snapshot(observedAt: observedAt, battery: 79),
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );

      expect(
        gateway.writes
            .where(
              (write) => write.payload.kind == SyncDocumentKind.deviceState,
            )
            .length,
        2,
      );
    });
  });

  group('Timestamps', () {
    test('the observation time is preserved verbatim through a write', () async {
      final gateway = _RecordingGateway();
      final service = _service(gateway: gateway);

      await service.publishNow(
        pairId: 'pair-1',
        snapshot: _snapshot(observedAt: observedAt),
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );

      final stateWrite = gateway.writes.firstWhere(
        (write) => write.payload.kind == SyncDocumentKind.deviceState,
      );
      // The device observed this at 10:02. Synchronization happening later — and
      // the server's own `updatedAt` — must never rewrite that fact
      // (Phase 20 §5, §19).
      expect(stateWrite.payload.fields['observedAt'], observedAt);
      expect(stateWrite.payload.observedAt, observedAt);
    });
  });

  group('Failure classification', () {
    test('authorization and validation codes are distinguished', () {
      expect(
        DeviceStateSyncService.classifyFailure('permission-denied'),
        SyncFailureKind.unauthorized,
      );
      expect(
        DeviceStateSyncService.classifyFailure('unauthenticated'),
        SyncFailureKind.unauthorized,
      );
      expect(
        DeviceStateSyncService.classifyFailure('invalid-argument'),
        SyncFailureKind.rejected,
      );
      expect(
        DeviceStateSyncService.classifyFailure('failed-precondition'),
        SyncFailureKind.rejected,
      );
      expect(
        DeviceStateSyncService.classifyFailure('unavailable'),
        SyncFailureKind.transient,
      );
      expect(
        DeviceStateSyncService.classifyFailure('deadline-exceeded'),
        SyncFailureKind.transient,
      );
      expect(
        DeviceStateSyncService.classifyFailure('network-request-failed'),
        SyncFailureKind.transient,
      );
      expect(
        DeviceStateSyncService.classifyFailure(null),
        SyncFailureKind.unknown,
      );
    });

    test('a refusal is blocked and is never retried', () async {
      final scheduler = _ManualScheduler();
      final gateway = _RecordingGateway(
        result: const SyncWriteResult.failed('permission-denied'),
      );
      final service = _service(gateway: gateway, scheduler: scheduler);

      service.requestPublish(_request(_snapshot(observedAt: observedAt)));
      scheduler.fire();
      await pumpEventQueue();

      expect(gateway.writes, hasLength(1));
      expect(scheduler.hasPending, isFalse);
      expect(service.retryAttempt, 0);
    });

    test('a transient failure is retried, but the budget is bounded', () async {
      final scheduler = _ManualScheduler();
      final gateway = _RecordingGateway(
        result: const SyncWriteResult.failed('unavailable'),
      );
      final service = _service(gateway: gateway, scheduler: scheduler);

      service.requestPublish(_request(_snapshot(observedAt: observedAt)));

      var runs = 0;
      while (scheduler.hasPending && runs < 20) {
        runs++;
        scheduler.fire();
        await pumpEventQueue();
      }

      // One initial attempt plus `maxRetryAttempts` retries, and then it stops
      // and waits for a new trigger instead of retrying forever
      // (Phase 20 §22, §27).
      expect(runs, DeviceStateSyncService.maxRetryAttempts + 1);
      expect(
        gateway.writes,
        hasLength(DeviceStateSyncService.maxRetryAttempts + 1),
      );
      expect(service.retryAttempt, 0);
    });

    test('the busy signal brackets a run', () async {
      final scheduler = _ManualScheduler();
      final gateway = _RecordingGateway();
      final service = _service(gateway: gateway, scheduler: scheduler);
      final busy = <bool>[];
      final subscription = service.busy.listen(busy.add);

      service.requestPublish(_request(_snapshot(observedAt: observedAt)));
      scheduler.fire();
      await pumpEventQueue();

      expect(busy, <bool>[true, false]);
      await subscription.cancel();
    });
  });

  group('Reset', () {
    test('forgets bookkeeping so a later session republishes', () async {
      final gateway = _RecordingGateway();
      final service = _service(gateway: gateway);
      final snapshot = _snapshot(observedAt: observedAt);

      await service.publishNow(
        pairId: 'pair-1',
        snapshot: snapshot,
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );
      await service.reset();
      final after = await service.publishNow(
        pairId: 'pair-1',
        snapshot: snapshot,
        sharedCategories: const {SharingCategory.battery},
        sharingPaused: false,
      );

      expect(
        after
            .firstWhere(
              (outcome) => outcome.kind == SyncDocumentKind.deviceState,
            )
            .decision,
        SyncDecision.published,
      );
      expect(
        gateway.writes
            .where(
              (write) => write.payload.kind == SyncDocumentKind.deviceState,
            )
            .length,
        2,
      );
    });

    test('nothing is deleted that was never published', () async {
      final gateway = _RecordingGateway();
      final service = _service(gateway: gateway);

      final outcomes = await service.publishNow(
        pairId: 'pair-1',
        snapshot: _snapshot(observedAt: observedAt),
        sharedCategories: const <SharingCategory>{},
        sharingPaused: true,
      );

      final state = outcomes.firstWhere(
        (outcome) => outcome.kind == SyncDocumentKind.deviceState,
      );
      expect(state.decision, SyncDecision.unchanged);
      expect(gateway.writes, isEmpty);
    });
  });
}

DeviceStateSyncService _service({
  required _RecordingGateway gateway,
  SyncScheduler? scheduler,
}) => DeviceStateSyncService(
  syncGateway: gateway,
  stateSanitizer: DeviceStateSanitizer(
    now: () => DateTime.utc(2026, 9, 28, 11, 16),
  ),
  versionCounter: _MemoryVersionStore(),
  scheduler: scheduler ?? ImmediateSyncScheduler(),
);

SyncRequest _request(DeviceStateSnapshot snapshot) => SyncRequest(
  pairId: 'pair-1',
  snapshot: snapshot,
  sharedCategories: const {SharingCategory.battery},
  sharingPaused: false,
);

DeviceStateSnapshot _snapshot({
  required DateTime observedAt,
  int battery = 80,
}) => DeviceStateSnapshot(
  deviceId: 'device-1',
  userId: 'user-a',
  collectedAt: observedAt,
  capabilities: const <DeviceMetric, StateObservation<Object?>>{},
  battery: BatteryState(
    percentage: StateObservation<int>(
      availability: CapabilityAvailability.available,
      value: battery,
      observedAt: observedAt,
    ),
    chargingState: const StateObservation<BatteryChargingState>(
      availability: CapabilityAvailability.available,
      value: BatteryChargingState.discharging,
    ),
    chargingDuration: const StateObservation<Duration>(
      availability: CapabilityAvailability.unknown,
    ),
    chargingSource: const StateObservation<BatteryChargingSource>(
      availability: CapabilityAvailability.unsupported,
    ),
  ),
);

/// A scheduler whose action only runs when the test says so, so retry and
/// coalescing behaviour is deterministic rather than timing-dependent.
class _ManualScheduler implements SyncScheduler {
  void Function()? _pending;

  @override
  bool get hasPending => _pending != null;

  @override
  void schedule(Duration delay, void Function() action) => _pending = action;

  @override
  void cancel() => _pending = null;

  void fire() {
    final action = _pending;
    _pending = null;
    action?.call();
  }
}

class _RecordingGateway implements DeviceStateSyncGateway {
  _RecordingGateway({this.result = const SyncWriteResult.published()});

  SyncWriteResult result;

  final List<({String pairId, String ownerId, SyncPayload payload})> writes =
      [];

  @override
  Future<SyncWriteResult> publish({
    required String pairId,
    required String ownerId,
    required SyncPayload payload,
  }) async {
    writes.add((pairId: pairId, ownerId: ownerId, payload: payload));
    return result;
  }

  @override
  Stream<RemoteStateDocument> watch({
    required String pairId,
    required String ownerId,
    required SyncDocumentKind kind,
  }) => const Stream<RemoteStateDocument>.empty();
}

class _MemoryVersionStore implements SyncVersionStore {
  int value = 0;

  @override
  Future<int> read() async => value;

  @override
  Future<void> write(int version) async => value = version;
}
