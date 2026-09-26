/// Platform-neutral battery source. Tests inject a fake instead of invoking
/// native channels.
abstract interface class BatteryPlatformGateway {
  Future<Object?> readCurrent();
  Stream<Object?> watchChanges();
  String get platformName;
}

/// Raw platform response. Invalid numeric values remain intact so collectors
/// reject them instead of silently clamping them.
class BatteryPlatformSample {
  const BatteryPlatformSample({
    required this.percentage,
    required this.chargingState,
    required this.chargingSource,
    required this.chargingSourceSupported,
  });

  final Object? percentage;
  final String? chargingState;
  final String? chargingSource;
  final bool chargingSourceSupported;

  factory BatteryPlatformSample.fromPlatform(Object? value) {
    // Test and in-process adapters may already return the normalized raw
    // sample. Native method/event channels still use the map representation.
    if (value is BatteryPlatformSample) return value;
    if (value is! Map) {
      throw const FormatException('Native battery response was not a map.');
    }
    return BatteryPlatformSample(
      percentage: value['percentage'],
      chargingState: value['chargingState'] as String?,
      chargingSource: value['chargingSource'] as String?,
      chargingSourceSupported: value['chargingSourceSupported'] == true,
    );
  }
}
