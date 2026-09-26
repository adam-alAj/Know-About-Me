import '../../../../core/domain/device_metric.dart';
import 'battery_state.dart';
import 'state_observation.dart';

export 'state_observation.dart';

enum CapabilitySupport {
  supported,
  unsupported,
  permissionRequired,
  temporarilyUnavailable,
  available,
}

/// A partial, point-in-time observation. Values originate on this device.
/// No interpretation or partner data is represented here.
class DeviceStateSnapshot {
  const DeviceStateSnapshot({
    required this.deviceId,
    this.userId,
    required this.collectedAt,
    required this.capabilities,
    this.reportedAt,
    this.battery,
  });

  final String deviceId;
  final String? userId;
  final DateTime collectedAt;
  final DateTime? reportedAt;
  final Map<DeviceMetric, StateObservation<Object?>> capabilities;
  final BatteryState? battery;

  DeviceStateSnapshot withBattery(BatteryState value, {DateTime? observedAt}) =>
      DeviceStateSnapshot(
        deviceId: deviceId,
        userId: userId,
        collectedAt: observedAt?.toUtc() ?? collectedAt,
        reportedAt: reportedAt,
        capabilities: capabilities,
        battery: value,
      );

  StateObservation<Object?>? operator [](DeviceMetric capability) => capabilities[capability];

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'userId': userId,
    'collectedAt': collectedAt.toUtc().toIso8601String(),
    'reportedAt': reportedAt?.toUtc().toIso8601String(),
    'battery': battery?.toJson(),
    'capabilities': {
      for (final entry in capabilities.entries) entry.key.name: entry.value.toJson(),
    },
  };

  factory DeviceStateSnapshot.fromJson(Map<String, Object?> json) {
    final raw = json['capabilities']! as Map<String, Object?>;
    return DeviceStateSnapshot(
      deviceId: json['deviceId']! as String,
      userId: json['userId'] as String?,
      collectedAt: DateTime.parse(json['collectedAt']! as String).toUtc(),
      reportedAt: json['reportedAt'] == null ? null : DateTime.parse(json['reportedAt']! as String).toUtc(),
      battery: json['battery'] == null
          ? null
          : BatteryState.fromJson(
              Map<String, Object?>.from(json['battery']! as Map),
            ),
      capabilities: {
        for (final entry in raw.entries)
          DeviceMetric.values.byName(entry.key): StateObservation<Object?>.fromJson(
            Map<String, Object?>.from(entry.value! as Map),
          ),
      },
    );
  }
}

/// Capability registry entry used by UI and collection orchestration.
class DeviceCapabilityStatus {
  const DeviceCapabilityStatus(this.support, {this.permission = DevicePermissionState.notApplicable});
  final CapabilitySupport support;
  final DevicePermissionState permission;
}
