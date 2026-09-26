import 'package:kam/core/domain/device_metric.dart';
import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/platform/device_platform.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/features/device_state/domain/models/device_capability.dart';
import 'package:kam/features/device_state/domain/models/device_state.dart';
import 'package:kam/features/device_state/domain/sources/device_state_source.dart';

/// Test double for [DeviceStateSource].
///
/// Configured per metric so tests can exercise supported, unsupported and
/// failed reads — the three cases the UI must render differently.
class FakeDeviceStateSource implements DeviceStateSource {
  FakeDeviceStateSource({
    this.platform = DevicePlatform.android,
    Map<DeviceMetric, MetricSupport>? support,
    this.state,
    this.failure,
  }) : _support = support ?? const <DeviceMetric, MetricSupport>{};

  final DevicePlatform platform;
  final Map<DeviceMetric, MetricSupport> _support;
  final DeviceState? state;
  final AppFailure? failure;

  @override
  DeviceCapabilityReport get capabilities =>
      DeviceCapabilityReport(platform: platform, support: _support);

  @override
  Future<Result<DeviceState>> readCurrentState() async {
    final failure = this.failure;
    if (failure != null) return Failure<DeviceState>(failure);
    return Success<DeviceState>(state ?? DeviceState.empty('fake-device'));
  }
}
