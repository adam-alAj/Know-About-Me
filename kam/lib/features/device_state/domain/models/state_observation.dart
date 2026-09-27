import '../../../../core/freshness/data_freshness.dart';

/// Normalized OS permission state; platform adapters map native values here.
enum DevicePermissionState {
  granted,
  denied,

  /// The user declined and the OS will not show the prompt again. The
  /// application must not keep asking (Phase 10, FR-056).
  permanentlyDenied,

  /// The OS blocks the permission for a reason the user cannot change here,
  /// for example parental controls or an MDM policy.
  restricted,

  /// Granted with reduced scope, for example approximate location.
  limited,

  notDetermined,

  /// The platform reports a permission but not which state it is in.
  unknown,

  notApplicable,
}

/// Why an observation does not currently have a usable value.
enum CapabilityAvailability {
  available,
  unavailable,
  unknown,
  unsupported,
  permissionDenied,

  /// The OS-level service that provides this metric is switched off, which is
  /// distinct from the app lacking permission (Phase 10: location services
  /// disabled is not the same as permission denied).
  serviceDisabled,

  error,
  stale,
}

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

  DataFreshness freshnessAt(
    DateTime now, [FreshnessPolicy policy = FreshnessPolicy.standard]
  ) {
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
      ? null
      : DateTime.parse(value as String).toUtc();
}
