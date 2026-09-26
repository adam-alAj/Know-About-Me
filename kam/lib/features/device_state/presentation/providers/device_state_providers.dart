import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/domain/device_metric.dart';
import '../../../../core/result/result.dart';
import '../../data/sources/unavailable_device_state_source.dart';
import '../../data/providers/platform_device_state_provider.dart';
import '../../data/battery/battery_platform_gateway.dart';
import '../../data/repositories/local_device_state_repository.dart';
import '../../data/services/app_device_identity.dart';
import '../../data/services/shared_preferences_device_identity_store.dart';
import '../../data/sources/unavailable_platform_device_state_adapter.dart';
import '../../domain/models/device_capability.dart';
import '../../domain/models/device_state.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/models/battery_state.dart';
import '../../domain/repositories/device_state_repository.dart';
import '../../domain/sources/device_state_provider.dart';
import '../../domain/sources/device_state_source.dart';
import '../../domain/services/battery_charging_collector.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// The device-state source for this platform.
///
/// Resolves to [UnavailableDeviceStateSource], which reports everything as
/// unsupported. The device-monitoring phase replaces this override with the real
/// Android/iOS collector. Tests override it with a fake.
final deviceStateSourceProvider = Provider<DeviceStateSource>(
  (ref) => UnavailableDeviceStateSource(
    platform: ref.watch(platformInfoProvider).platform,
  ),
);

/// What this platform/device can actually observe (FR-068).
final deviceCapabilityReportProvider = Provider<DeviceCapabilityReport>(
  (ref) => ref.watch(deviceStateSourceProvider).capabilities,
);

/// Capability of a single metric, used by the UI to explain why a value is
/// missing rather than showing a guess.
final deviceCapabilityProvider = Provider.family<MetricSupport, DeviceMetric>(
  (ref, metric) => ref.watch(deviceCapabilityReportProvider).supportFor(metric),
);

/// This device's current observable state.
///
/// Carried as `Result` so the UI can distinguish "read failed" from "read
/// succeeded but the metric is unknown" (SRS NFR-007, NFR-014).
final currentDeviceStateProvider = FutureProvider<Result<DeviceState>>(
  (ref) => ref.watch(deviceStateSourceProvider).readCurrentState(),
);

/// App-generated opaque ID; stored locally and unrelated to authorization.
final appDeviceIdentityProvider = Provider<AppDeviceIdentity>(
  (ref) => AppDeviceIdentity(SharedPreferencesDeviceIdentityStore()),
);

final batteryChargingCollectorProvider = Provider<BatteryChargingCollector>((ref) {
  final platform = ref.watch(platformInfoProvider).platform;
  final collector = BatteryChargingCollector(
    gateway: MethodChannelBatteryGateway(platform.name),
    now: () => ref.read(clockProvider).nowUtc(),
  );
  ref.onDispose(collector.dispose);
  return collector;
});

/// Current local battery observation, independent of network and pairing.
final currentLocalBatteryStateProvider = FutureProvider<BatteryState>(
  (ref) => ref.watch(batteryChargingCollectorProvider).refresh(),
);

/// Local snapshot provider. Unauthenticated use gets an empty owner scope; no
/// remote operation is exposed here. Phase 11 will require auth and pair rules.
final deviceStateProvider = Provider<DeviceStateProvider>((ref) {
  final adapter = UnavailablePlatformDeviceStateAdapter(
    ref.watch(platformInfoProvider).platform,
  );
  return PlatformDeviceStateProvider(
    deviceId: () => ref.read(appDeviceIdentityProvider).getOrCreate(),
    userId: () => ref.read(currentIdentityProvider)?.uid,
    adapter: adapter,
    clock: () => ref.read(clockProvider).nowUtc(),
    logger: ref.watch(loggerProvider),
    batteryCollector: ref.watch(batteryChargingCollectorProvider),
  );
});

final localDeviceStateRepositoryProvider = Provider<DeviceStateRepository>(
  (ref) => LocalDeviceStateRepository(ref.watch(deviceStateProvider)),
);

final deviceMonitoringControllerProvider = Provider<DeviceMonitoringController>((ref) {
  final controller = DeviceMonitoringController(ref.watch(localDeviceStateRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

final currentLocalDeviceStateProvider = FutureProvider<DeviceStateSnapshot>(
  (ref) async {
    ref.watch(currentIdentityProvider);
    final repository = LocalDeviceStateRepository(ref.watch(deviceStateProvider));
    return repository.getCurrentLocalState();
  },
);
