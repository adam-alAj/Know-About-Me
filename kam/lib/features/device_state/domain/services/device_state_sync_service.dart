import 'dart:async';

import '../../../privacy/domain/models/sharing_category.dart';
import '../models/device_state_snapshot.dart';
import '../models/sync_payload.dart';
import '../sources/device_state_sync_gateway.dart';
import '../sources/sync_version_store.dart';
import 'device_state_sanitizer.dart';
import 'sync_change_tracker.dart';
import 'sync_scheduler.dart';

/// What the service decided for one document.
enum SyncDecision {
  /// A changed, permitted payload was written.
  published,

  /// Sharing was withdrawn, so the document was removed.
  deleted,

  /// The payload carried nothing new, so no write was made.
  unchanged,

  /// Sharing is on but nothing trustworthy could be published right now; the
  /// previously synchronized document is left as it was.
  withheld,

  /// The write was attempted and rejected or failed. The change is *not*
  /// recorded, so the next trigger retries the latest state.
  failed,
}

/// The outcome for one synchronized document.
class SyncOutcome {
  const SyncOutcome(this.kind, this.decision, {this.reason});

  final SyncDocumentKind kind;
  final SyncDecision decision;

  /// A safe technical reason, never a data value.
  final String? reason;

  bool get isFailure => decision == SyncDecision.failed;

  @override
  String toString() =>
      'SyncOutcome(${kind.name}: ${decision.name}'
      '${reason == null ? '' : ', $reason'})';
}

/// One request to synchronize the current local state.
class SyncRequest {
  const SyncRequest({
    required this.pairId,
    required this.snapshot,
    required this.sharedCategories,
    required this.sharingPaused,
  });

  final String pairId;
  final DeviceStateSnapshot snapshot;
  final Set<SharingCategory> sharedCategories;
  final bool sharingPaused;

  @override
  String toString() =>
      'SyncRequest(pair: $pairId, categories: ${sharedCategories.length}, '
      'paused: $sharingPaused)';
}

/// Publishes this device's own state and nothing else.
///
/// The service is a pure decision + write pipeline:
///
/// ```text
/// local snapshot → sanitize → change check → version → Firestore
/// ```
///
/// Guarantees:
/// * the owner id is supplied by the caller from authenticated application
///   state, never from user input;
/// * a write only happens when the meaningful content changed, so a repeated
///   refresh cannot produce a duplicate document update;
/// * requests that arrive while a write is in flight are collapsed into the
///   single latest one, so an older snapshot can never overwrite a newer one;
/// * `observedAt` always comes from the device observation and `updatedAt` from
///   the server, so the two are never conflated.
class DeviceStateSyncService {
  DeviceStateSyncService({
    required DeviceStateSyncGateway syncGateway,
    required DeviceStateSanitizer stateSanitizer,
    required SyncVersionStore versionCounter,
    SyncChangeTracker? changeTracker,
    SyncScheduler? scheduler,
    this.coalesceWindow = const Duration(seconds: 3),
  }) : _gateway = syncGateway,
       _sanitizer = stateSanitizer,
       _versionStore = versionCounter,
       _changeTracker = changeTracker ?? SyncChangeTracker(),
       _scheduler = scheduler ?? TimerSyncScheduler();

  final DeviceStateSyncGateway _gateway;
  final DeviceStateSanitizer _sanitizer;
  final SyncVersionStore _versionStore;
  final SyncChangeTracker _changeTracker;
  final SyncScheduler _scheduler;

  /// How long bursts of local change are coalesced before a write is attempted.
  final Duration coalesceWindow;

  final StreamController<List<SyncOutcome>> _results =
      StreamController<List<SyncOutcome>>.broadcast();

  SyncRequest? _latest;
  bool _running = false;
  int? _version;
  bool _disposed = false;

  /// The outcome of every completed synchronization run.
  Stream<List<SyncOutcome>> get results => _results.stream;

  /// Whether a write is currently in flight.
  bool get isBusy => _running;

  /// The newest version this device has issued in this session.
  int? get currentVersion => _version;

  /// Publishes immediately, bypassing coalescing.
  ///
  /// Used by an explicit "sync now" action and by the tests.
  Future<List<SyncOutcome>> publishNow({
    required String pairId,
    required DeviceStateSnapshot snapshot,
    required Set<SharingCategory> sharedCategories,
    required bool sharingPaused,
  }) async {
    if (_disposed) return const <SyncOutcome>[];

    final deviceState = _sanitizer.sanitizeDeviceState(
      snapshot: snapshot,
      ownerUserId: _requireOwner(snapshot),
      sharedCategories: sharedCategories,
      sharingPaused: sharingPaused,
      stateVersion: 0,
    );
    final location = _sanitizer.sanitizeLocation(
      snapshot: snapshot,
      ownerUserId: _requireOwner(snapshot),
      sharedCategories: sharedCategories,
      sharingPaused: sharingPaused,
      stateVersion: 0,
    );

    final outcomes = <SyncOutcome>[];
    final pending = <SyncPayload>[];

    for (final payload in <SyncPayload>[deviceState, location]) {
      if (!payload.shareable) {
        if (payload.retract) {
          outcomes.add(await _retract(pairId, snapshot, payload));
        } else {
          outcomes.add(SyncOutcome(payload.kind, SyncDecision.withheld));
        }
        continue;
      }
      if (!_changeTracker.hasChanged(payload)) {
        outcomes.add(SyncOutcome(payload.kind, SyncDecision.unchanged));
        continue;
      }
      pending.add(payload);
    }

    // One version per generation: both documents written in this run describe
    // the same local state, so they share the version that identifies it.
    if (pending.isNotEmpty) {
      final version = await _nextVersion();
      for (final payload in pending) {
        outcomes.add(await _write(pairId, payload.withVersion(version)));
      }
    }

    return outcomes;
  }

  /// Requests a coalesced publish of [request].
  ///
  /// Repeated calls inside [coalesceWindow] produce one write. A request that
  /// arrives while a write is in flight is remembered and re-run afterwards
  /// with the latest state, so nothing is lost and nothing is written twice.
  void requestPublish(SyncRequest request) {
    if (_disposed) return;
    _latest = request;
    _scheduler.schedule(coalesceWindow, _drain);
  }

  /// Forgets all publication bookkeeping.
  ///
  /// Called on sign-out, on pair change and on disconnection, so that a later
  /// session never treats previous bookkeeping as up to date and never deletes
  /// a document it did not publish.
  Future<void> reset() async {
    _scheduler.cancel();
    _latest = null;
    _changeTracker.reset();
    _version = null;
    _versionLoad = null;
    if (!_results.isClosed) _results.add(const <SyncOutcome>[]);
  }

  /// Releases the timer and the result stream.
  Future<void> dispose() async {
    _disposed = true;
    _scheduler.cancel();
    await _results.close();
  }

  // ------------------------------------------------------------- internals --

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_latest != null && !_disposed) {
        final request = _latest!;
        _latest = null;
        final outcomes = await publishNow(
          pairId: request.pairId,
          snapshot: request.snapshot,
          sharedCategories: request.sharedCategories,
          sharingPaused: request.sharingPaused,
        );
        if (!_results.isClosed) _results.add(outcomes);
      }
    } finally {
      _running = false;
    }
  }

  Future<SyncOutcome> _write(String pairId, SyncPayload payload) async {
    try {
      final result = await _gateway.publish(
        pairId: pairId,
        ownerId: _ownerOf(payload),
        payload: payload,
      );
      if (result.isFailure) {
        // The change is deliberately not recorded: the next trigger retries
        // the latest state instead of replaying a queue (Phase 11 §17, §19).
        return SyncOutcome(
          payload.kind,
          SyncDecision.failed,
          reason: result.reason ?? 'write_failed',
        );
      }
      _changeTracker.recordPublished(payload);
      return SyncOutcome(payload.kind, SyncDecision.published);
    } catch (error) {
      return SyncOutcome(
        payload.kind,
        SyncDecision.failed,
        reason: error.runtimeType.toString(),
      );
    }
  }

  Future<SyncOutcome> _retract(
    String pairId,
    DeviceStateSnapshot snapshot,
    SyncPayload payload,
  ) async {
    if (!_changeTracker.hasPublished(payload.kind)) {
      // Nothing was ever published, so there is nothing to remove.
      return SyncOutcome(payload.kind, SyncDecision.unchanged);
    }
    try {
      final result = await _gateway.publish(
        pairId: pairId,
        ownerId: _requireOwner(snapshot),
        payload: payload,
      );
      if (result.isFailure) {
        return SyncOutcome(
          payload.kind,
          SyncDecision.failed,
          reason: result.reason ?? 'delete_failed',
        );
      }
      _changeTracker.forget(payload.kind);
      return SyncOutcome(payload.kind, SyncDecision.deleted);
    } catch (error) {
      return SyncOutcome(
        payload.kind,
        SyncDecision.failed,
        reason: error.runtimeType.toString(),
      );
    }
  }

  Future<int>? _versionLoad;

  /// Issues the next monotonic version.
  Future<int> _nextVersion() async {
    final loaded = _versionLoad ??= _loadVersion();
    final current = _version ?? await loaded;
    final next = current + 1;
    _version = next;
    _versionLoad = Future<int>.value(next);
    // Persistence is best-effort: losing the counter costs at most a repeated
    // version after a restart, never an incorrect write.
    try {
      await _versionStore.write(next);
    } catch (_) {
      // A storage failure must not fail the synchronization itself.
    }
    return next;
  }

  Future<int> _loadVersion() async {
    try {
      return await _versionStore.read();
    } catch (_) {
      return 0;
    }
  }

  String _requireOwner(DeviceStateSnapshot snapshot) {
    final owner = snapshot.userId;
    if (owner == null || owner.isEmpty) {
      throw StateError('Cannot synchronize without an authenticated owner');
    }
    return owner;
  }

  /// The owner id recorded inside the payload, which the sanitizer took from the
  /// authenticated snapshot rather than from user input.
  String _ownerOf(SyncPayload payload) {
    final owner = payload.fields['ownerUserId'];
    if (owner is! String || owner.isEmpty) {
      throw StateError('Payload has no owner');
    }
    return owner;
  }
}
