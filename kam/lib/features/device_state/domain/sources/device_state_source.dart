import '../../../../core/result/result.dart';
import '../models/device_capability.dart';
import '../models/device_state.dart';

/// Contract for reading this device's observable state.
///
/// Android and iOS need different implementations, so the rest of the
/// application depends on this interface rather than on any plugin (SRS
/// constraint 3, NFR-017). Implementations:
///
/// - must declare what they support via [capabilities] instead of returning
///   placeholder numbers (FR-068),
/// - must return `MetricValue.unsupported()/unknown()/unavailable()` when a
///   value cannot be determined, never a fabricated value (constraint 4),
/// - must return [Failure] rather than throwing, so the UI can classify it.
///
/// Phase 2 ships no real implementation; `UnavailableDeviceStateSource` is the
/// honest placeholder. Native collectors arrive in Phase 4.
abstract interface class DeviceStateSource {
  /// Which metrics this platform/device can provide.
  DeviceCapabilityReport get capabilities;

  /// Reads the current state once.
  Future<Result<DeviceState>> readCurrentState();

  // A `Stream<DeviceState> watch()` is intentionally omitted until Phase 4,
  // when the background execution strategy (WorkManager / BGTaskScheduler) is
  // decided. Adding it now would promise a real-time guarantee the platforms
  // do not offer. See docs/platform/PLATFORM_CAPABILITIES.md.
}
