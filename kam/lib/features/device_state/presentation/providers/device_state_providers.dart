import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/domain/device_metric.dart';
import '../../../../core/result/result.dart';
import '../../data/sources/unavailable_device_state_source.dart';
import '../../domain/models/device_capability.dart';
import '../../domain/models/device_state.dart';
import '../../domain/sources/device_state_source.dart';

/// The device-state source for this platform.
///
/// Phase 2 resolves to [UnavailableDeviceStateSource], which reports everything
/// as unsupported. Phase 4 replaces this override with the real Android/iOS
/// collector. Tests override it with a fake.
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
