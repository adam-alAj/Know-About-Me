import '../../../../core/domain/device_metric.dart';
import 'activity_state.dart';
import 'battery_state.dart';
import 'device_availability_evidence.dart';
import 'device_location_state.dart';
import 'network_state.dart';
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
    this.network,
    this.activity,
    this.location,
    this.availability,
  });

  final String deviceId;
  final String? userId;
  final DateTime collectedAt;
  final DateTime? reportedAt;
  final Map<DeviceMetric, StateObservation<Object?>> capabilities;
  final BatteryState? battery;
  final NetworkState? network;

  /// Activity observations (display, signal status, app lifecycle), when the
  /// activity collector is wired in.
  final ActivityState? activity;

  /// Location, permission, home distance and presence observations, when the
  /// location collector is wired in. Home coordinates are not part of this
  /// contract — only derived values leave the device.
  final DeviceLocationState? location;

  /// Evidence-based local availability derived from every observation in this
  /// snapshot plus the last observed activity signal.
  final DeviceAvailabilityEvidence? availability;

  DeviceStateSnapshot withBattery(BatteryState value, {DateTime? observedAt}) =>
      DeviceStateSnapshot(
        deviceId: deviceId,
        userId: userId,
        collectedAt: observedAt?.toUtc() ?? collectedAt,
        reportedAt: reportedAt,
        capabilities: capabilities,
        battery: value,
        network: network,
        activity: activity,
        location: location,
        availability: availability,
      );

  DeviceStateSnapshot withNetwork(NetworkState value, {DateTime? observedAt}) =>
      DeviceStateSnapshot(
        deviceId: deviceId,
        userId: userId,
        collectedAt: observedAt?.toUtc() ?? collectedAt,
        reportedAt: reportedAt,
        capabilities: capabilities,
        battery: battery,
        network: value,
        activity: activity,
        location: location,
        availability: availability,
      );

  DeviceStateSnapshot withActivity(ActivityState value, {DateTime? observedAt}) =>
      DeviceStateSnapshot(
        deviceId: deviceId,
        userId: userId,
        collectedAt: observedAt?.toUtc() ?? collectedAt,
        reportedAt: reportedAt,
        capabilities: capabilities,
        battery: battery,
        network: network,
        activity: value,
        location: location,
        availability: availability,
      );

  DeviceStateSnapshot withLocation(
    DeviceLocationState value, {
    DateTime? observedAt,
  }) => DeviceStateSnapshot(
    deviceId: deviceId,
    userId: userId,
    collectedAt: observedAt?.toUtc() ?? collectedAt,
    reportedAt: reportedAt,
    capabilities: capabilities,
    battery: battery,
    network: network,
    activity: activity,
    location: value,
    availability: availability,
  );

  DeviceStateSnapshot withAvailability(DeviceAvailabilityEvidence value) =>
      DeviceStateSnapshot(
        deviceId: deviceId,
        userId: userId,
        collectedAt: collectedAt,
        reportedAt: reportedAt,
        capabilities: capabilities,
        battery: battery,
        network: network,
        activity: activity,
        location: location,
        availability: value,
      );

  StateObservation<Object?>? operator [](DeviceMetric capability) => capabilities[capability];

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'userId': userId,
    'collectedAt': collectedAt.toUtc().toIso8601String(),
    'reportedAt': reportedAt?.toUtc().toIso8601String(),
    'battery': battery?.toJson(),
    'network': network?.toJson(),
    'activity': activity?.toJson(),
    'location': location?.toJson(),
    'availability': availability?.toJson(),
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
      network: json['network'] == null
          ? null
          : NetworkState.fromJson(
              Map<String, Object?>.from(json['network']! as Map),
            ),
      activity: json['activity'] == null
          ? null
          : ActivityState.fromJson(
              Map<String, Object?>.from(json['activity']! as Map),
            ),
      location: json['location'] == null
          ? null
          : DeviceLocationState.fromJson(
              Map<String, Object?>.from(json['location']! as Map),
            ),
      availability: json['availability'] == null
          ? null
          : DeviceAvailabilityEvidence.fromJson(
              Map<String, Object?>.from(json['availability']! as Map),
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
