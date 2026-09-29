import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/features/device_state/data/sync/device_state_sync_coordinator.dart';
import 'package:kam/features/device_state/domain/models/battery_state.dart';
import 'package:kam/features/device_state/domain/models/device_state_snapshot.dart';
import 'package:kam/features/device_state/domain/models/pair_sharing_state.dart';
import 'package:kam/features/device_state/domain/models/remote_device_state.dart';
import 'package:kam/features/device_state/domain/models/sync_payload.dart';
import 'package:kam/features/device_state/domain/services/device_state_sanitizer.dart';
import 'package:kam/features/device_state/domain/services/device_state_sync_service.dart';
import 'package:kam/features/device_state/domain/services/sync_scheduler.dart';
import 'package:kam/features/device_state/domain/sources/device_state_sync_gateway.dart';
import 'package:kam/features/device_state/domain/sources/sync_version_store.dart';
import 'package:kam/features/pairing/domain/models/partner_scope.dart';
import 'package:kam/features/privacy/domain/models/sharing_category.dart';

/// Phase 20 §11, §12, §16: going offline must not delete the data this device
/// legitimately published, and a privacy change made offline must take effect
/// locally at once rather than waiting for Firestore.
void main() {
  final observedAt = DateTime.utc(2026, 9, 28, 10, 2);
  const scope = PartnerScope(pairId: 'pair-1', partnerUserId: 'user-b');

  test('nothing is ever published without an active pair', () {
    final scheduler = _ManualScheduler();
    final gateway = _RecordingGateway();
    final coordinator = _coordinator(gateway: gateway, scheduler: scheduler);

    coordinator.onLocalSnapshot(_snapshot(observedAt: observedAt));

    expect(scheduler.hasPending, isFalse);
    expect(gateway.writes, isEmpty);
  });

  test('a cache-only sharing value does not retract published data', () async {
    final scheduler = _ManualScheduler();
    final gateway = _RecordingGateway();
    final coordinator = _coordinator(gateway: gateway, scheduler: scheduler);
    await coordinator.updateScope(scope);

    coordinator.updateSharing(
      const PairSharingState(
        paused: false,
        categories: {SharingCategory.battery},
      ),
    );
    final published = await coordinator.publishNow(
      _snapshot(observedAt: observedAt),
    );
    expect(
      published.map((outcome) => outcome.decision),
      contains(SyncDecision.published),
    );

    // The device goes offline. `ownSharingProvider` now serves a cache-only
    // value, which the wiring passes as `null` — "unknown", not "share nothing".
    // Treating it as a decision would delete the user's own document just
    // because the connection dropped (Phase 20 §11, §27).
    coordinator.applyConfirmedSharing(null);
    expect(scheduler.hasPending, isFalse);
    expect(coordinator.isActive, isTrue);
    expect(gateway.deletes, isEmpty);
  });

  test('a locally pending privacy change takes effect at once', () async {
    final scheduler = _ManualScheduler();
    final gateway = _RecordingGateway();
    final coordinator = _coordinator(gateway: gateway, scheduler: scheduler);
    await coordinator.updateScope(scope);

    // Sharing battery, confirmed by our own unacknowledged local write: the
    // user made this decision offline, so `isConfirmed` is true.
    const sharingBattery = PairSharingState(
      paused: false,
      categories: {SharingCategory.battery},
      isFromCache: true,
      hasPendingWrites: true,
    );
    expect(sharingBattery.isConfirmed, isTrue);
    coordinator.applyConfirmedSharing(sharingBattery);
    coordinator.onLocalSnapshot(_snapshot(observedAt: observedAt));
    scheduler.fire();
    await pumpEventQueue();
    expect(gateway.writes, hasLength(1));

    // Same offline session: the user pauses sharing entirely.
    const pausedLocally = PairSharingState(
      paused: true,
      categories: {},
      isFromCache: true,
      hasPendingWrites: true,
    );
    coordinator.applyConfirmedSharing(pausedLocally);
    scheduler.fire();
    await pumpEventQueue();

    // The previously published document is retracted immediately, without
    // waiting for the backend to confirm the privacy switch.
    expect(gateway.deletes, hasLength(1));
    expect(gateway.deletes.single.payload.retract, isTrue);
    expect(coordinator.isActive, isFalse);
  });

  test('a cache-only value with no local write is not a decision', () {
    const cachedOnly = PairSharingState(
      paused: false,
      categories: {SharingCategory.battery},
      isFromCache: true,
    );
    expect(cachedOnly.isConfirmed, isFalse);
  });

  test('changing the pair discards the previous pairing bookkeeping', () async {
    final gateway = _RecordingGateway();
    final coordinator = _coordinator(gateway: gateway);
    await coordinator.updateScope(scope);
    coordinator.updateSharing(
      const PairSharingState(
        paused: false,
        categories: {SharingCategory.battery},
      ),
    );
    await coordinator.publishNow(_snapshot(observedAt: observedAt));

    await coordinator.updateScope(
      const PartnerScope(pairId: 'pair-2', partnerUserId: 'user-c'),
    );

    expect(coordinator.scope?.pairId, 'pair-2');
    expect(coordinator.isActive, isTrue);
  });
}

DeviceStateSyncCoordinator _coordinator({
  required _RecordingGateway gateway,
  SyncScheduler? scheduler,
}) => DeviceStateSyncCoordinator(
  DeviceStateSyncService(
    syncGateway: gateway,
    stateSanitizer: DeviceStateSanitizer(
      now: () => DateTime.utc(2026, 9, 28, 11, 16),
    ),
    versionCounter: _MemoryVersionStore(),
    scheduler: scheduler ?? ImmediateSyncScheduler(),
  ),
);

DeviceStateSnapshot _snapshot({required DateTime observedAt}) =>
    DeviceStateSnapshot(
      deviceId: 'device-1',
      userId: 'user-a',
      collectedAt: observedAt,
      capabilities: const <DeviceMetric, StateObservation<Object?>>{},
      battery: BatteryState(
        percentage: StateObservation<int>(
          availability: CapabilityAvailability.available,
          value: 80,
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
  final List<({String pairId, String ownerId, SyncPayload payload})> writes =
      [];

  List<({String pairId, String ownerId, SyncPayload payload})> get deletes =>
      writes.where((write) => write.payload.retract).toList();

  @override
  Future<SyncWriteResult> publish({
    required String pairId,
    required String ownerId,
    required SyncPayload payload,
  }) async {
    writes.add((pairId: pairId, ownerId: ownerId, payload: payload));
    return payload.retract
        ? const SyncWriteResult.deleted()
        : const SyncWriteResult.published();
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
