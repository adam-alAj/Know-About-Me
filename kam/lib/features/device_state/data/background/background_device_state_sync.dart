import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kam_background_monitoring/kam_background_monitoring.dart';

import '../../../../core/logging/app_logger.dart';
import '../services/app_device_identity.dart';
import '../../domain/models/activity_state.dart';
import '../../domain/models/battery_state.dart';
import '../../domain/models/device_availability_evidence.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/models/network_state.dart';
import '../../domain/services/device_state_sanitizer.dart';
import '../../../privacy/domain/models/sharing_category.dart';

/// Periodic, authenticated source-device sampling and publication.
///
/// It uses the same domain sanitizer and Firestore document contract as the
/// foreground publisher. Only battery, network and interactive-display state
/// are collected; location and human-activity history are never sampled here.
class BackgroundDeviceStateSync {
  BackgroundDeviceStateSync(
    this._firestore, {
    required this.deviceIdentity,
    required this.readVersion,
    required this.writeVersion,
    this.now = _utcNow,
    this.logger = const DeveloperAppLogger(),
  });

  final FirebaseFirestore _firestore;
  final AppDeviceIdentity deviceIdentity;
  final Future<int> Function() readVersion;
  final Future<void> Function(int version) writeVersion;
  final DateTime Function() now;
  final AppLogger logger;

  static DateTime _utcNow() => DateTime.now().toUtc();

  static const _deviceStateCategories = <SharingCategory>{
    SharingCategory.battery,
    SharingCategory.charging,
    SharingCategory.network,
    SharingCategory.activityIndicators,
  };

  /// Samples the phone only when an active, mutually consented pair currently
  /// shares at least one device-state category, then publishes this owner's
  /// own pair-scoped document. Server rules remain authoritative.
  Future<int> publishFor(String authenticatedUserId) async {
    final pairs = await _firestore
        .collection('pairs')
        .where('memberIds', arrayContains: authenticatedUserId)
        .get(const GetOptions(source: Source.server));

    final eligiblePairs =
        <(DocumentReference<Map<String, dynamic>>, Set<SharingCategory>)>[];
    for (final pairSnapshot in pairs.docs) {
      final pairData = pairSnapshot.data();
      final memberIds = (pairData['memberIds'] as List?)
          ?.whereType<String>()
          .toList(growable: false);
      if (pairData['status'] != 'active' ||
          memberIds == null ||
          memberIds.length != 2 ||
          !memberIds.contains(authenticatedUserId)) {
        continue;
      }

      final consents = await Future.wait(
        memberIds.map(
          (memberId) => pairSnapshot.reference
              .collection('consents')
              .doc(memberId)
              .get(const GetOptions(source: Source.server)),
        ),
      );
      if (consents.any((consent) => consent.data()?['granted'] != true)) {
        continue;
      }

      final sharingSnapshot = await pairSnapshot.reference
          .collection('sharing')
          .doc(authenticatedUserId)
          .get(const GetOptions(source: Source.server));
      final sharing = sharingSnapshot.data();
      if (sharing == null || sharing['paused'] != false) continue;
      final categories = _parseCategories(sharing['categories']);
      if (categories.intersection(_deviceStateCategories).isEmpty) continue;
      eligiblePairs.add((pairSnapshot.reference, categories));
    }

    if (eligiblePairs.isEmpty) {
      logger.info(
        'BACKGROUND_DEVICE_SYNC_SKIPPED',
        context: {'reason': 'no_active_consented_device_state_sharing'},
      );
      return 0;
    }

    final sample = await KamBackgroundMonitoring.collectSupportedState();
    if (sample['appVisible'] == true) {
      logger.info(
        'BACKGROUND_DEVICE_SYNC_SKIPPED',
        context: {'reason': 'app_is_visible'},
      );
      return 0;
    }
    final snapshot = _snapshot(
      sample,
      authenticatedUserId,
      await deviceIdentity.getOrCreate(),
    );
    var highestVersion = await readVersion();
    final sanitizer = DeviceStateSanitizer(now: now);

    for (final (pairReference, categories) in eligiblePairs) {
      final document = pairReference
          .collection('deviceState')
          .doc(authenticatedUserId);
      final committedVersion = await _firestore.runTransaction<int>((
        transaction,
      ) async {
        final current = await transaction.get(document);
        final previousVersion = current.data()?['stateVersion'];
        final baseVersion =
            previousVersion is int && previousVersion > highestVersion
            ? previousVersion
            : highestVersion;
        final nextVersion = baseVersion + 1;
        final payload = sanitizer.sanitizeDeviceState(
          snapshot: snapshot,
          ownerUserId: authenticatedUserId,
          sharedCategories: categories,
          sharingPaused: false,
          stateVersion: nextVersion,
        );
        final fields = <String, Object?>{
          ...payload.fields,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        for (final field in payload.clearedFields) {
          fields[field] = FieldValue.delete();
        }
        transaction.set(document, fields, SetOptions(merge: true));
        return nextVersion;
      });
      if (committedVersion > highestVersion) highestVersion = committedVersion;
    }

    await writeVersion(highestVersion);
    logger.info(
      'BACKGROUND_DEVICE_SYNC_SUCCEEDED',
      context: {
        'pairCount': eligiblePairs.length,
        'stateVersion': highestVersion,
        'observationAgeSeconds': now()
            .difference(snapshot.collectedAt)
            .inSeconds,
      },
    );
    return eligiblePairs.length;
  }

  DeviceStateSnapshot _snapshot(
    Map<String, Object?> sample,
    String ownerId,
    String deviceId,
  ) => snapshotFromSample(
    sample,
    ownerId: ownerId,
    deviceId: deviceId,
    fallbackObservedAt: now().toUtc(),
  );

  /// Converts native observations into the existing domain snapshot without
  /// fabricating durations, location, or human-activity history.
  static DeviceStateSnapshot snapshotFromSample(
    Map<String, Object?> sample, {
    required String ownerId,
    required String deviceId,
    required DateTime fallbackObservedAt,
  }) {
    final epochMillis = sample['observedAtEpochMillis'];
    final observedAt = epochMillis is int
        ? DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true)
        : fallbackObservedAt.toUtc();
    StateObservation<T> observation<T>(T? value) => StateObservation<T>(
      availability: value == null
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: value,
      observedAt: value == null ? null : observedAt,
      updatedAt: value == null ? null : observedAt,
      source: 'android_workmanager',
      platform: 'android',
    );

    final percentage = sample['batteryPercentage'];
    final rawCharging = sample['chargingState'];
    final chargingState = _enumValue(
      BatteryChargingState.values,
      rawCharging,
      BatteryChargingState.unknown,
    );
    final rawSource = sample['chargingSource'];
    final chargingSource = _enumValue(
      BatteryChargingSource.values,
      rawSource,
      BatteryChargingSource.unknown,
    );
    final battery = BatteryState(
      percentage: observation<int>(percentage is int ? percentage : null),
      chargingState: observation<BatteryChargingState>(
        chargingState == BatteryChargingState.unknown ? null : chargingState,
      ),
      // A periodic sample cannot prove an uninterrupted charge interval.
      chargingDuration: const StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
      ),
      chargingSource: observation<BatteryChargingSource>(
        chargingSource == BatteryChargingSource.unknown ? null : chargingSource,
      ),
    );

    final connectivityType = _enumValue(
      ConnectivityType.values,
      sample['connectivityType'],
      ConnectivityType.unknown,
    );
    final rawInternet = sample['internetReachability'];
    final internet = _enumValue(
      InternetReachability.values,
      rawInternet,
      InternetReachability.unknown,
    );
    final rawNetworkStatus = sample['networkStatus'];
    final networkStatus = _enumValue(
      NetworkOnlineStatus.values,
      rawNetworkStatus,
      NetworkOnlineStatus.unknown,
    );
    final network = NetworkState(
      connectivity: observation<ConnectivityType>(
        connectivityType == ConnectivityType.unknown ? null : connectivityType,
      ),
      internet: observation<InternetReachability>(
        internet == InternetReachability.unknown ? null : internet,
      ),
      status: observation<NetworkOnlineStatus>(
        networkStatus == NetworkOnlineStatus.unknown ? null : networkStatus,
      ),
      offlineDuration: const StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
      ),
    );

    final screenState = _enumValue(
      DeviceScreenState.values,
      sample['screenState'],
      DeviceScreenState.unknown,
    );
    final activity = ActivityState(
      screenState: observation<DeviceScreenState>(
        screenState == DeviceScreenState.unknown ? null : screenState,
      ),
      activityStatus: const StateObservation<ActivityStatus>(
        availability: CapabilityAvailability.unknown,
        value: ActivityStatus.unknown,
      ),
      appLifecycle: StateObservation<AppLifecyclePhase>(
        availability: CapabilityAvailability.available,
        value: AppLifecyclePhase.background,
        observedAt: observedAt,
        updatedAt: observedAt,
        source: 'android_workmanager',
        platform: 'android',
      ),
      activityDuration: const StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
      ),
    );

    final hasEvidence =
        percentage is int ||
        chargingState != BatteryChargingState.unknown ||
        networkStatus != NetworkOnlineStatus.unknown ||
        screenState != DeviceScreenState.unknown;
    return DeviceStateSnapshot(
      deviceId: deviceId,
      userId: ownerId,
      collectedAt: observedAt,
      capabilities: const {},
      battery: battery,
      network: network,
      activity: activity,
      availability: DeviceAvailabilityEvidence(
        availability: hasEvidence
            ? CapabilityAvailability.available
            : CapabilityAvailability.unknown,
        observedAt: observedAt,
        lastConfirmedAvailableAt: hasEvidence ? observedAt : null,
        source: 'android_workmanager',
      ),
    );
  }

  static Set<SharingCategory> _parseCategories(Object? raw) {
    if (raw is! List) return const {};
    return {
      for (final name in raw.whereType<String>())
        for (final category in SharingCategory.values)
          if (category.name == name) category,
    };
  }

  static T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }
}
