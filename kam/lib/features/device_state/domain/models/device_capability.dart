import '../../../../core/domain/device_metric.dart';
import '../../../../core/platform/device_platform.dart';

/// How well a platform can provide one metric.
enum MetricSupport {
  /// The metric can be observed with the required permissions granted.
  supported,

  /// The metric is observable, but only after the user grants a permission
  /// (for example location).
  requiresPermission,

  /// The platform or device cannot provide this metric at all (FR-068).
  unsupported,
}

/// Which metrics the current platform/device can actually provide.
///
/// This is the honest capability statement that later collectors are measured
/// against. A metric absent from [support] is treated as
/// [MetricSupport.unsupported] rather than assumed to work (SRS FR-068, NFR-019).
class DeviceCapabilityReport {
  const DeviceCapabilityReport({required this.platform, required this.support});

  /// A report claiming nothing is supported.
  ///
  /// This is the correct Phase 2 value: no native collectors exist yet, and
  /// guessing capabilities would violate SRS constraint 4.
  factory DeviceCapabilityReport.none(DevicePlatform platform) =>
      DeviceCapabilityReport(
        platform: platform,
        support: const <DeviceMetric, MetricSupport>{},
      );

  /// The platform this report describes.
  final DevicePlatform platform;

  /// Explicit per-metric support. Missing keys mean unsupported.
  final Map<DeviceMetric, MetricSupport> support;

  /// Support level for [metric]; defaults to unsupported.
  MetricSupport supportFor(DeviceMetric metric) =>
      support[metric] ?? MetricSupport.unsupported;

  /// Whether [metric] can be observed right now.
  bool isSupported(DeviceMetric metric) =>
      supportFor(metric) == MetricSupport.supported;

  /// Whether [metric] is observable once a permission is granted.
  bool requiresPermission(DeviceMetric metric) =>
      supportFor(metric) == MetricSupport.requiresPermission;

  /// Whether the platform cannot provide [metric] at all.
  bool isUnsupported(DeviceMetric metric) =>
      supportFor(metric) == MetricSupport.unsupported;

  @override
  String toString() =>
      'DeviceCapabilityReport(${platform.name}, ${support.length} metrics)';
}
