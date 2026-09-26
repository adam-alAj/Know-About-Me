import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/domain/device_metric.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/repositories/device_state_repository.dart';
import '../../domain/sources/device_state_provider.dart';
import '../../domain/sources/platform_device_state_adapter.dart';

/// Collects capabilities independently. A single native API failure becomes
/// an error observation and does not discard successful sibling observations.
class PlatformDeviceStateProvider implements DeviceStateProvider {
  PlatformDeviceStateProvider({
    required this.deviceId,
    required this.userId,
    required this.adapter,
    required this.clock,
    required this.logger,
  });

  final Future<String> Function() deviceId;
  final String? Function() userId;
  final PlatformDeviceStateAdapter adapter;
  final DateTime Function() clock;
  final AppLogger logger;

  @override
  Map<DeviceMetric, DeviceCapabilityStatus> getCapabilityStatus() => {
    for (final capability in DeviceMetric.values)
      capability: adapter.capabilityStatus(capability),
  };

  @override
  Future<DeviceStateSnapshot> getCurrentState() async {
    final collectedAt = clock().toUtc();
    logger.info('Device state collection started');
    final observations = <DeviceMetric, StateObservation<Object?>>{};
    for (final capability in DeviceMetric.values) {
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
    logger.info('Device state collection completed', context: {
      'capabilityCount': observations.length,
    });
    return DeviceStateSnapshot(
      deviceId: await deviceId(),
      userId: userId(),
      collectedAt: collectedAt,
      capabilities: Map.unmodifiable(observations),
    );
  }

  @override
  Stream<DeviceStateSnapshot> watchState() async* {
    yield await getCurrentState();
  }
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

  Future<void> stopMonitoring() async {
    await _subscription?.cancel();
    _subscription = null;
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
