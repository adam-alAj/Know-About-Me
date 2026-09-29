import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/domain/device_metric.dart';
import '../../domain/models/device_availability_evidence.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/repositories/device_state_repository.dart';
import '../../domain/sources/device_state_provider.dart';
import '../../domain/sources/platform_device_state_adapter.dart';
import '../../domain/services/activity_state_collector.dart';
import '../../domain/services/battery_charging_collector.dart';
import '../../domain/services/device_availability_deriver.dart';
import '../../domain/services/location_state_collector.dart';
import '../../domain/services/network_state_collector.dart';


/// Collects capabilities independently. A single native API failure becomes
/// an error observation and does not discard successful sibling observations.
class PlatformDeviceStateProvider implements DeviceStateProvider {
  PlatformDeviceStateProvider({
    required this.deviceId,
    required this.userId,
    required this.adapter,
    required this.clock,
    required this.logger,
    this.batteryCollector,
    this.networkCollector,
    this.activityCollector,
    this.locationCollector,
  });

  final Future<String> Function() deviceId;
  final String? Function() userId;
  final PlatformDeviceStateAdapter adapter;
  final DateTime Function() clock;
  final AppLogger logger;
  final BatteryChargingCollector? batteryCollector;
  final NetworkStateCollector? networkCollector;
  final ActivityStateCollector? activityCollector;
  final LocationStateCollector? locationCollector;

  static const _deriver = DeviceAvailabilityDeriver();

  @override
  Map<DeviceMetric, DeviceCapabilityStatus> getCapabilityStatus() {
    final status = <DeviceMetric, DeviceCapabilityStatus>{
      for (final capability in DeviceMetric.values)
        capability: adapter.capabilityStatus(capability),
    };
    final battery = batteryCollector;
    if (battery != null) status.addAll(battery.capabilityStatus);
    final network = networkCollector;
    if (network != null) status.addAll(network.capabilityStatus);
    final activity = activityCollector;
    if (activity != null) status.addAll(activity.capabilityStatus);
    final location = locationCollector;
    if (location != null) status.addAll(location.capabilityStatus);
    return Map.unmodifiable(status);
  }

  @override
  Future<DeviceStateSnapshot> getCurrentState() async {
    final collectedAt = clock().toUtc();
    logger.info('Device state collection started');
    final observations = <DeviceMetric, StateObservation<Object?>>{};
    for (final capability in DeviceMetric.values) {
      // Without a battery collector, retain Phase 6's generic adapter path so
      // existing platforms and test adapters can still supply those metrics.
      if ((batteryCollector != null && _batteryMetrics.contains(capability)) ||
          (networkCollector != null && _networkMetrics.contains(capability)) ||
          (activityCollector != null &&
              _activityMetrics.contains(capability)) ||
          (locationCollector != null &&
              _locationMetrics.contains(capability))) {
        continue;
      }
      try {
        final observation = await adapter.collect(capability);
        observations[capability] = observation;
        if (observation.availability != CapabilityAvailability.available) {
          logger.info('Device capability is not currently available', context: {
            'capability': capability.name,
            'availability': observation.availability.name,
          });
        }
      } catch (error) {
        logger.warning('Device capability collection failed', context: {
          'capability': capability.name,
          'errorType': error.runtimeType.toString(),
        });
        observations[capability] = StateObservation<Object?>(
          availability: CapabilityAvailability.error,
          source: 'platform_adapter',
          platform: adapter.platformName,
          error: 'Temporary collection failure',
          updatedAt: clock().toUtc(),
        );
      }
    }
    final battery = batteryCollector == null
        ? null
        : await batteryCollector!.refresh();
    final network = networkCollector == null
        ? null
        : await networkCollector!.refresh();
    // Activity collection fails independently: a display-read failure still
    // yields an ActivityState with an error observation, never an exception.
    final activity = activityCollector == null
        ? null
        : await activityCollector!.refresh();
    // Location is the most expensive collector and the most sensitive one: it
    // reads only when permission and the OS service allow it, and a failure
    // becomes a normalized state rather than an exception.
    final location = locationCollector == null
        ? null
        : await locationCollector!.refresh();
    logger.info('Device state collection completed', context: {
      'capabilityCount': observations.length,
    });
    final snapshot = DeviceStateSnapshot(
      deviceId: await deviceId(),
      userId: userId(),
      collectedAt: collectedAt,
      capabilities: Map.unmodifiable(observations),
      battery: battery,
      network: network,
      activity: activity,
      location: location,
    );
    return snapshot.withAvailability(_deriveAvailability(snapshot));
  }

  /// Conservative local availability: evidence from every observation in the
  /// snapshot plus the last observed activity signal. Never a power-state
  /// claim; see `docs/device-state/ACTIVITY_AVAILABILITY.md`.
  DeviceAvailabilityEvidence _deriveAvailability(
    DeviceStateSnapshot snapshot,
  ) {
    final observations = <StateObservation<Object?>>[
      ...snapshot.capabilities.values,
      ...?snapshot.battery?.observations,
      ...?snapshot.network?.observations,
      ...?snapshot.activity?.observations,
      ...?snapshot.location?.observations,
    ];
    return _deriver.derive(
      observations: observations,
      lastObservedActivityAt: snapshot.activity?.lastObservedActivityAt,
      now: clock().toUtc(),
    );
  }

  @override
  Stream<DeviceStateSnapshot> watchState() async* {
    var snapshot = await getCurrentState();
    yield snapshot;
    final collector = batteryCollector;
    final network = networkCollector;
    final activity = activityCollector;
    final location = locationCollector;
    if (collector == null &&
        network == null &&
        activity == null &&
        location == null) {
      return;
    }

    final updates = StreamController<DeviceStateSnapshot>();
    final subscriptions = <Future<void> Function()>[];
    if (collector != null) {
      final subscription = collector.watchBatteryState().listen((battery) {
        snapshot = snapshot.withBattery(battery, observedAt: clock().toUtc());
        snapshot = snapshot.withAvailability(_deriveAvailability(snapshot));
        updates.add(snapshot);
      }, onError: updates.addError);
      subscriptions.add(subscription.cancel);
    }
    if (network != null) {
      final subscription = network.watchNetworkState().listen((value) {
        snapshot = snapshot.withNetwork(value, observedAt: clock().toUtc());
        snapshot = snapshot.withAvailability(_deriveAvailability(snapshot));
        updates.add(snapshot);
      }, onError: updates.addError);
      subscriptions.add(subscription.cancel);
    }
    if (activity != null) {
      final subscription = activity.watchActivityState().listen((value) {
        snapshot = snapshot.withActivity(value, observedAt: clock().toUtc());
        snapshot = snapshot.withAvailability(_deriveAvailability(snapshot));
        updates.add(snapshot);
      }, onError: updates.addError);
      subscriptions.add(subscription.cancel);
    }
    if (location != null) {
      final subscription = location.watchLocationState().listen((value) {
        snapshot = snapshot.withLocation(value, observedAt: clock().toUtc());
        snapshot = snapshot.withAvailability(_deriveAvailability(snapshot));
        updates.add(snapshot);
      }, onError: updates.addError);
      subscriptions.add(subscription.cancel);
    }
    try {
      yield* updates.stream;
    } finally {
      for (final cancel in subscriptions) {
        await cancel();
      }
      await updates.close();
    }
  }

  static const _batteryMetrics = <DeviceMetric>{
    DeviceMetric.batteryPercentage,
    DeviceMetric.chargingState,
    DeviceMetric.chargingDuration,
    DeviceMetric.chargingSource,
  };

  static const _networkMetrics = <DeviceMetric>{
    DeviceMetric.networkStatus,
    DeviceMetric.networkConnectivity,
    DeviceMetric.internetReachability,
    DeviceMetric.offlineDuration,
  };

  static const _activityMetrics = <DeviceMetric>{
    DeviceMetric.screenState,
    DeviceMetric.activityState,
    DeviceMetric.lastActivity,
    DeviceMetric.appLifecycle,
    DeviceMetric.deviceAvailability,
  };

  static const _locationMetrics = <DeviceMetric>{
    DeviceMetric.location,
    DeviceMetric.preciseLocation,
    DeviceMetric.approximateLocation,
    DeviceMetric.backgroundLocation,
    DeviceMetric.homeLocation,
    DeviceMetric.distanceFromHome,
    DeviceMetric.homePresence,
  };
}

/// Small lifecycle-aware command surface. A caller starts/stops observation;
/// this foundation does not poll in the background.
class DeviceMonitoringController {
  DeviceMonitoringController(this._repository);
  final DeviceStateRepository _repository;
  final _snapshots = StreamController<DeviceStateSnapshot>.broadcast();
  StreamSubscription<DeviceStateSnapshot>? _subscription;

  Stream<DeviceStateSnapshot> get snapshots => _snapshots.stream;

  Future<void> startMonitoring() async {
    if (_subscription != null) return;
    _subscription = _repository.watchLocalState().listen(
      _snapshots.add,
      onError: _snapshots.addError,
      onDone: () => _subscription = null,
    );
  }

  /// Releases the platform subscription.
  ///
  /// The handle is cleared *before* the cancellation is awaited. Otherwise a
  /// lifecycle flap (inactive → resumed, for example while a system dialog is
  /// dismissed) can call [startMonitoring] while a cancelled subscription is
  /// still stored: it would see a non-null handle, do nothing, and leave the
  /// application with no observation at all (Phase 20 §20, §21).
  Future<void> stopMonitoring() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  Future<DeviceStateSnapshot> collectNow() => _repository.refresh();

  Future<void> dispose() async {
    await stopMonitoring();
    // A broadcast stream's close future may remain pending when nobody is
    // listening for its done event. Closing is still initiated; disposal must
    // not hang the lifecycle while waiting for an optional listener.
    unawaited(_snapshots.close());
  }
}
