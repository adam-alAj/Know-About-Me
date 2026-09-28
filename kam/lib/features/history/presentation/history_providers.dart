import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../app/providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../pairing/presentation/providers/pairing_providers.dart';
import '../../device_state/domain/models/state_observation.dart';
import '../../device_state/domain/models/battery_state.dart';
import '../../device_state/domain/models/network_state.dart';
import '../../device_state/presentation/providers/device_state_providers.dart';
import '../../device_state/presentation/providers/sync_providers.dart';
import '../../privacy/domain/models/sharing_category.dart';
import '../../rules/presentation/providers/rule_evaluation_providers.dart';
import '../../rules/domain/models/interpretation_result.dart';
import '../data/firestore_history_repository.dart';
import '../data/shared_preferences_history_repository.dart';
import '../domain/models/device_event.dart';
import '../domain/repositories/history_repository.dart';

final localHistoryRepositoryProvider = Provider<HistoryRepository>(
  (ref) => SharedPreferencesHistoryRepository(now: () => ref.read(clockProvider).nowUtc()),
);

final firestoreHistoryRepositoryProvider = Provider<FirestoreHistoryRepository?>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) return null;
  return FirestoreHistoryRepository(ref.watch(firebaseFirestoreProvider));
});

/// Writes locally first. Firestore's offline queue handles transient network
/// loss; authorization failures leave the bounded local copy intact.
final historyRecorderProvider = Provider<HistoryRecorder>((ref) => HistoryRecorder(
  local: ref.watch(localHistoryRepositoryProvider),
  remote: ref.watch(firestoreHistoryRepositoryProvider),
));

/// One app-root listener set records only real charging/connectivity changes
/// and rule outcome transitions. It is pair-aware, sharing-aware and disposed
/// with the root provider scope.
final historyEventListenersProvider = Provider<void>((ref) {
  ref.listen(monitoredDeviceStateProvider, (previous, next) {
    final before = previous?.value;
    final after = next.value;
    if (before == null || after == null) return;
    final scope = ref.read(partnerScopeProvider).value;
    final uid = ref.read(currentIdentityProvider)?.uid;
    final sharing = ref.read(ownSharingProvider).value;
    if (scope == null || uid == null || sharing == null || sharing.paused) return;
    final recorder = ref.read(historyRecorderProvider);
    final now = after.collectedAt.toUtc();
    final oldCharge = _available(before.battery?.chargingState);
    final newCharge = _available(after.battery?.chargingState);
    if (sharing.categories.contains(SharingCategory.charging) && oldCharge != null && newCharge != null && oldCharge != newCharge) {
      final started = newCharge == BatteryChargingState.charging;
      if (started || oldCharge == BatteryChargingState.charging) {
        final type = started ? DeviceEventType.chargingStarted : DeviceEventType.chargingStopped;
        final observedAt = after.battery?.chargingState.observedAt;
        unawaited(recorder.record(_event(
          scope.pairId, uid, after.deviceId, type, observedAt?.toUtc() ?? now,
          source: 'device', summary: started ? 'Charging started' : 'Charging stopped',
          transition: '${oldCharge.name}_to_${newCharge.name}',
          observedAt: observedAt,
        )));
      }
    }
    final oldNetwork = _available(before.network?.status);
    final newNetwork = _available(after.network?.status);
    if (sharing.categories.contains(SharingCategory.network) && oldNetwork != null && newNetwork != null && oldNetwork != newNetwork) {
      if (oldNetwork == NetworkOnlineStatus.online || oldNetwork == NetworkOnlineStatus.offline) {
        if (newNetwork == NetworkOnlineStatus.online || newNetwork == NetworkOnlineStatus.offline) {
          final becameOnline = newNetwork == NetworkOnlineStatus.online;
          unawaited(recorder.record(_event(
            scope.pairId, uid, after.deviceId,
            becameOnline ? DeviceEventType.deviceCameOnline : DeviceEventType.deviceWentOffline,
            after.network?.status.observedAt?.toUtc() ?? now,
            source: 'device',
            observedAt: after.network?.status.observedAt,
            summary: becameOnline ? 'Connectivity available again' : 'Connectivity unavailable',
            transition: '${oldNetwork.name}_to_${newNetwork.name}',
          )));
        }
      }
    }
  });

  ref.listen(ruleEvaluationProvider, (previous, next) {
    if (!next.hasPartnerState || next.evaluatedAt == null) return;
    final scope = ref.read(partnerScopeProvider).value;
    final uid = ref.read(currentIdentityProvider)?.uid;
    final sharing = ref.read(ownSharingProvider).value;
    if (scope == null || uid == null || sharing == null || sharing.paused ||
        !sharing.categories.contains(SharingCategory.ruleInterpretations)) {
      return;
    }
    final at = next.evaluatedAt!.toUtc();
    final recorder = ref.read(historyRecorderProvider);
    for (final result in next.transitions) {
      final type = switch (result.transition) {
        RuleTransition.becameMatched => DeviceEventType.ruleActivated,
        RuleTransition.becameNotMatched => DeviceEventType.ruleDeactivated,
        RuleTransition.becameIndeterminate => DeviceEventType.ruleBecameUnknown,
        RuleTransition.stayedMatched || RuleTransition.stayedNotMatched ||
        RuleTransition.stayedIndeterminate => null,
      };
      if (type == null) continue;
      final key = '${scope.pairId}|$uid|${result.ruleId}|v${result.ruleVersion}|${type.name}|${at.toIso8601String()}';
      unawaited(recorder.record(DeviceEvent(
        id: historyEventId(key), pairId: scope.pairId, ownerUserId: uid,
        type: type, occurredAt: at, observedAt: result.observationTime,
        source: 'rule', deduplicationKey: historyEventId(key),
        summary: switch (type) {
          DeviceEventType.ruleActivated => 'A shared rule matched',
          DeviceEventType.ruleDeactivated => 'A shared rule no longer matched',
          _ => 'A shared rule could not be evaluated',
        },
        payload: <String, Object?>{'outcome': result.status.name, 'ruleVersion': result.ruleVersion},
      )));
      if (type == DeviceEventType.ruleActivated &&
          (result.title != null || result.userDefinedProbability != null)) {
        final interpretationKey = '$key|interpretation';
        unawaited(recorder.record(DeviceEvent(
          id: historyEventId(interpretationKey), pairId: scope.pairId,
          ownerUserId: uid, type: DeviceEventType.interpretationGenerated,
          occurredAt: at, observedAt: result.observationTime, source: 'rule',
          deduplicationKey: historyEventId(interpretationKey),
          summary: 'A user-defined rule interpretation was generated',
          payload: <String, Object?>{'outcome': result.status.name, 'ruleVersion': result.ruleVersion},
        )));
      }
    }
  });
});

T? _available<T>(StateObservation<T>? observation) =>
    observation?.availability == CapabilityAvailability.available ? observation?.value : null;

DeviceEvent _event(String pairId, String uid, String deviceId, DeviceEventType type,
    DateTime at, {required String source, required String summary, required String transition,
    DateTime? observedAt}) {
  final key = '$pairId|$uid|${type.name}|$transition|${at.toIso8601String()}';
  return DeviceEvent(
    id: historyEventId(key), pairId: pairId, ownerUserId: uid, deviceId: deviceId,
    type: type, occurredAt: at, observedAt: observedAt, source: source,
    deduplicationKey: historyEventId(key), summary: summary,
    payload: <String, Object?>{'transition': transition},
  );
}

class HistoryRecorder {
  HistoryRecorder({required this.local, required this.remote});
  final HistoryRepository local;
  final FirestoreHistoryRepository? remote;

  Future<void> record(DeviceEvent event) async {
    try {
      await local.add(event);
    } on Object {
      // Event recording is best-effort and must not interrupt device or rule UI.
    }
    try {
      await remote?.add(event);
    } on Object {
      // Local history remains available; Firestore errors are not fatal to UI.
    }
  }

  Future<void> clear({required String pairId, required String ownerUserId}) async {
    try {
      await local.clearLocal();
    } on Object {
      // A local storage failure should not prevent attempting remote deletion.
    }
    try {
      await remote?.deleteOwnedHistory(pairId: pairId, ownerUserId: ownerUserId);
    } on Object {
      // The local copy has already been cleared. Surface remote failures through
      // a later reload rather than failing the screen's deletion action.
    }
  }
}

final historyEventsProvider = StreamProvider.family<List<DeviceEvent>, EventCategory?>((ref, category) {
  final scope = ref.watch(partnerScopeProvider).value;
  final remote = ref.watch(firestoreHistoryRepositoryProvider);
  final local = ref.watch(localHistoryRepositoryProvider);
  if (scope == null || remote == null) {
    return Stream<List<DeviceEvent>>.fromFuture(local.page(category: category, limit: 100));
  }
  return remote.watch(pairId: scope.pairId, category: category).asyncMap((remoteEvents) async {
    final cached = await local.page(category: category, limit: 100);
    final byId = <String, DeviceEvent>{
      for (final event in remoteEvents) event.id: event,
      for (final event in cached.where((event) => event.pairId == scope.pairId)) event.id: event,
    };
    final merged = byId.values.toList()
      ..sort((a, b) {
        final order = (b.recordedAt ?? b.occurredAt).compareTo(a.recordedAt ?? a.occurredAt);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    return merged.take(100).toList();
  }).transform(StreamTransformer<List<DeviceEvent>, List<DeviceEvent>>.fromHandlers(
    handleError: (error, stackTrace, sink) {
      unawaited(local.page(category: category, limit: 100).then(sink.add));
    },
  ));
});

/// Opaque deterministic ID from a transition key. IDs never contain user text
/// or an internal Firestore document identifier.
String historyEventId(String stableKey) {
  var first = 0x811c9dc5;
  var second = 0x9e3779b9;
  for (final unit in stableKey.codeUnits) {
    first = ((first ^ unit) * 0x01000193) & 0xffffffff;
    second = ((second + unit) * 0x85ebca6b) & 0xffffffff;
  }
  return '${first.toRadixString(16).padLeft(8, '0')}${second.toRadixString(16).padLeft(8, '0')}';
}
