import '../../../../core/domain/device_metric.dart';
import '../../../../core/freshness/data_freshness.dart';

/// Normalized OS permission state. This is deliberately independent of any
/// permission plugin so platform adapters can map native states explicitly.
enum DevicePermissionState {
  granted,
  denied,
  restricted,
  limited,
  notDetermined,
  notApplicable,
}

/// Why an individual observed value is or is not available.
enum CapabilityAvailability {
  available,
  unavailable,
  unknown,
  unsupported,
  permissionDenied,
  error,
  stale,
}

enum CapabilitySupport {
  supported,
  unsupported,
  permissionRequired,
  temporarilyUnavailable,
  available,
}

/// A capability reading, including the reason it may not have a value.
class StateObservation<T> {
  const StateObservation({
    required this.availability,
    this.value,
    this.observedAt,
    this.updatedAt,
    this.source,
    this.permissionState,
    this.platform,
    this.error,
  });

  final CapabilityAvailability availability;
  final T? value;
  final DateTime? observedAt;
  final DateTime? updatedAt;
  final String? source;
  final DevicePermissionState? permissionState;
  final String? platform;
  final String? error;

  DataFreshness freshnessAt(DateTime now, [FreshnessPolicy policy = FreshnessPolicy.standard]) {
    if (availability == CapabilityAvailability.stale) return DataFreshness.stale;
    final observed = observedAt;
    if (observed == null) return DataFreshness.unknown;
    return policy.classifyAge(now.toUtc().difference(observed.toUtc()));
  }

  Map<String, Object?> toJson({Object? Function(T value)? encodeValue}) {
    final currentValue = value;
    final serializedValue = currentValue == null
        ? null
        : encodeValue?.call(currentValue) ?? currentValue;

    return {
      'availability': availability.name,
      'value': serializedValue,
      'observedAt': observedAt?.toUtc().toIso8601String(),
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
      'source': source,
      'permissionState': permissionState?.name,
      'platform': platform,
      'error': error,
    };
  }

  factory StateObservation.fromJson(
    Map<String, Object?> json, {
    T Function(Object? value)? decodeValue,
  }) {
    final rawValue = json['value'];
    final T? parsedValue;
    if (rawValue == null) {
      parsedValue = null;
    } else if (decodeValue != null) {
      parsedValue = decodeValue(rawValue);
    } else {
      parsedValue = rawValue as T;
    }

    return StateObservation<T>(
      availability: CapabilityAvailability.values.byName(
        json['availability']! as String,
      ),
      value: parsedValue,
      observedAt: _date(json['observedAt']),
      updatedAt: _date(json['updatedAt']),
      source: json['source'] as String?,
      permissionState: json['permissionState'] == null
          ? null
          : DevicePermissionState.values.byName(
              json['permissionState']! as String,
            ),
      platform: json['platform'] as String?,
      error: json['error'] as String?,
    );
  }

  static DateTime? _date(Object? value) => value == null
      ? null : DateTime.parse(value as String).toUtc();
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
  });

  final String deviceId;
  final String? userId;
  final DateTime collectedAt;
  final DateTime? reportedAt;
  final Map<DeviceMetric, StateObservation<Object?>> capabilities;

  StateObservation<Object?>? operator [](DeviceMetric capability) => capabilities[capability];

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'userId': userId,
    'collectedAt': collectedAt.toUtc().toIso8601String(),
    'reportedAt': reportedAt?.toUtc().toIso8601String(),
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
