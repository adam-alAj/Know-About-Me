import '../../../../core/freshness/data_freshness.dart';
import 'state_observation.dart';

/// Platform-normalized battery power state. `unknown` is a value reported by
/// the API; a missing/error result belongs in [StateObservation.availability].
enum BatteryChargingState { charging, full, discharging, notCharging, unknown }

/// Charger type is populated only when the platform reports it directly.
enum BatteryChargingSource { usb, ac, wireless, unknown }

class BatteryState {
  const BatteryState({
    required this.percentage,
    required this.chargingState,
    required this.chargingDuration,
    required this.chargingSource,
    this.chargingStartedAt,
  });

  final StateObservation<int> percentage;
  final StateObservation<BatteryChargingState> chargingState;
  final StateObservation<Duration> chargingDuration;
  final StateObservation<BatteryChargingSource> chargingSource;
  final DateTime? chargingStartedAt;

  Map<String, Object?> toJson() => {
    'percentage': percentage.toJson(),
    'chargingState': chargingState.toJson(encodeValue: (value) => value.name),
    'chargingDuration': chargingDuration.toJson(
      encodeValue: (value) => value.inMilliseconds,
    ),
    'chargingSource': chargingSource.toJson(encodeValue: (value) => value.name),
    'chargingStartedAt': chargingStartedAt?.toUtc().toIso8601String(),
  };

  factory BatteryState.fromJson(Map<String, Object?> json) => BatteryState(
    percentage: StateObservation<int>.fromJson(
      Map<String, Object?>.from(json['percentage']! as Map),
    ),
    chargingState: StateObservation<BatteryChargingState>.fromJson(
      Map<String, Object?>.from(json['chargingState']! as Map),
      decodeValue: (value) => BatteryChargingState.values.byName(value! as String),
    ),
    chargingDuration: StateObservation<Duration>.fromJson(
      Map<String, Object?>.from(json['chargingDuration']! as Map),
      decodeValue: (value) => Duration(milliseconds: value! as int),
    ),
    chargingSource: StateObservation<BatteryChargingSource>.fromJson(
      Map<String, Object?>.from(json['chargingSource']! as Map),
      decodeValue: (value) => BatteryChargingSource.values.byName(value! as String),
    ),
    chargingStartedAt: json['chargingStartedAt'] == null
        ? null
        : DateTime.parse(json['chargingStartedAt']! as String).toUtc(),
  );

  static const unknown = BatteryState(
    percentage: StateObservation<int>(availability: CapabilityAvailability.unknown),
    chargingState: StateObservation<BatteryChargingState>(
      availability: CapabilityAvailability.unknown,
      value: BatteryChargingState.unknown,
    ),
    chargingDuration: StateObservation<Duration>(
      availability: CapabilityAvailability.unknown,
    ),
    chargingSource: StateObservation<BatteryChargingSource>(
      availability: CapabilityAvailability.unsupported,
    ),
  );

  DataFreshness freshnessAt(DateTime now) {
    final timestamps = [percentage, chargingState]
        .map((observation) => observation.freshnessAt(now));
    if (timestamps.contains(DataFreshness.stale)) return DataFreshness.stale;
    if (timestamps.contains(DataFreshness.recent)) return DataFreshness.recent;
    if (timestamps.contains(DataFreshness.fresh)) return DataFreshness.fresh;
    return DataFreshness.unknown;
  }
}
