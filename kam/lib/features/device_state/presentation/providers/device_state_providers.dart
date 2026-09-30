import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/domain/device_metric.dart';
import '../../../../core/result/result.dart';
import '../../data/sources/unavailable_device_state_source.dart';
import '../../data/providers/platform_device_state_provider.dart';
import '../../data/activity/method_channel_activity_gateway.dart';
import '../../data/battery/battery_platform_gateway.dart';
import '../../data/location/method_channel_location_gateway.dart';
import '../../data/maps/method_channel_map_launcher.dart';
import '../../data/network/method_channel_network_gateway.dart';
import '../../data/services/shared_preferences_activity_observation_store.dart';
import '../../data/services/shared_preferences_location_observation_store.dart';
import '../../data/services/shared_preferences_network_observation_store.dart';
import '../../data/repositories/local_device_state_repository.dart';
import '../../data/services/app_device_identity.dart';
import '../../data/services/shared_preferences_device_identity_store.dart';
import '../../data/sources/unavailable_platform_device_state_adapter.dart';
import '../../domain/models/device_capability.dart';
import '../../domain/models/device_state.dart';
import '../../domain/models/device_state_snapshot.dart';
import '../../domain/models/battery_state.dart';
import '../../domain/models/network_state.dart';
import '../../domain/repositories/device_state_repository.dart';
import '../../domain/sources/device_state_provider.dart';
import '../../domain/sources/device_state_source.dart';
import '../../domain/sources/map_launcher.dart';
import '../../domain/models/activity_state.dart';
import '../../domain/models/device_location_state.dart';
import '../../domain/services/activity_state_collector.dart';
import '../../domain/services/battery_charging_collector.dart';
import '../../domain/services/location_state_collector.dart';
import '../../domain/services/network_state_collector.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// The device-state source for this platform.
///
/// Resolves to [UnavailableDeviceStateSource], which reports unsupported
/// capabilities on non-Android targets. Android monitoring uses the native
/// collectors below; tests override this provider with a fake.
final deviceStateSourceProvider = Provider<DeviceStateSource>(
  (ref) => UnavailableDeviceStateSource(
    platform: ref.watch(platformInfoProvider).platform,
  ),
);

/// Opens an authorized coordinate in the platform's map application (FR-025).
///
/// It carries no location data of its own and never decides authorization: the
/// UI only offers the action for coordinates the partner has already shared.
final mapLauncherProvider = Provider<MapLauncher>(
  (ref) => MethodChannelMapLauncher(ref.watch(platformInfoProvider).platform.name),
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

final networkStateCollectorProvider = Provider<NetworkStateCollector>((ref) {
  final platform = ref.watch(platformInfoProvider).platform;
  final collector = NetworkStateCollector(
    gateway: MethodChannelNetworkGateway(platform.name),
    now: () => ref.read(clockProvider).nowUtc(),
    store: SharedPreferencesNetworkObservationStore(),
  );
  ref.onDispose(collector.dispose);
  return collector;
});

/// Current local network observation; it never probes Firebase or depends on
/// authentication, pairing, or the remote synchronization layer.
final currentLocalNetworkStateProvider = StreamProvider<NetworkState>((ref) async* {
  final collector = ref.watch(networkStateCollectorProvider);
  // The root DeviceMonitoringLifecycle owns start/stop. This provider observes
  // its events without creating a second monitoring lifecycle.
  yield await collector.refresh();
  yield* collector.updates;
});

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
    networkCollector: ref.watch(networkStateCollectorProvider),
    activityCollector: ref.watch(activityStateCollectorProvider),
    locationCollector: ref.watch(locationStateCollectorProvider),
  );
});

final activityStateCollectorProvider = Provider<ActivityStateCollector>((ref) {
  final platform = ref.watch(platformInfoProvider).platform;
  final collector = ActivityStateCollector(
    gateway: MethodChannelActivityGateway(platform.name),
    store: SharedPreferencesActivityObservationStore(),
    now: () => ref.read(clockProvider).nowUtc(),
  );
  ref.onDispose(collector.dispose);
  return collector;
});

/// Current local activity observation; app lifecycle reports are pushed into
/// the collector by the root `DeviceMonitoringLifecycle`. It never probes
/// Firebase and never fabricates an activity timestamp.
final currentLocalActivityStateProvider = StreamProvider<ActivityState>((ref) async* {
  final collector = ref.watch(activityStateCollectorProvider);
  // The root DeviceMonitoringLifecycle owns start/stop. This provider observes
  // its events without creating a second monitoring lifecycle.
  yield await collector.refresh();
  yield* collector.updates;
});

/// Location collection: permission/service status, one fix per refresh and
/// platform-throttled updates. Home comes from the owner-only profile
/// preferences and is never inferred from movement.
final locationStateCollectorProvider = Provider<LocationStateCollector>((ref) {
  final platform = ref.watch(platformInfoProvider).platform;
  final collector = LocationStateCollector(
    gateway: MethodChannelLocationGateway(platform.name),
    store: SharedPreferencesLocationObservationStore(),
    now: () => ref.read(clockProvider).nowUtc(),
  );
  ref.onDispose(collector.dispose);
  // A watch here would recreate the collector on every preference change, so
  // the home location is pushed with a listener instead.
  ref.listen(currentUserPreferencesProvider, (_, next) {
    collector.setHomeLocation(next.value?.valueOrNull?.homeLocation);
  }, fireImmediately: true);
  return collector;
});

/// Current local location observation; ownership of start/stop stays with the
/// root monitoring lifecycle.
final currentLocalLocationStateProvider =
    StreamProvider<DeviceLocationState>((ref) async* {
      final collector = ref.watch(locationStateCollectorProvider);
      yield await collector.refresh();
      yield* collector.updates;
    });

/// The latest local snapshot streamed by the root monitoring lifecycle, used
/// by the debug view to surface evidence-based availability.
final monitoredDeviceStateProvider = StreamProvider<DeviceStateSnapshot>(
  (ref) => ref.watch(deviceMonitoringControllerProvider).snapshots,
);

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
