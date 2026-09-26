import 'metric_value.dart';

/// Charging state as reported by the platform (SRS FR-009).
///
/// There is deliberately no "powered off" state anywhere in the device-state
/// model: a phone cannot reliably report its own power-off, so the SRS
/// (FR-015, FR-070) forbids claiming it.
enum ChargingState {
  charging,
  notCharging,
  fullyCharged,

  /// The platform could not report a charging state.
  unknown,
}

/// Network connectivity as observed by the device (SRS FR-012).
enum NetworkStatus {
  /// Reachable, transport unknown.
  online,

  /// Not currently reachable.
  offline,

  /// Reachable over Wi-Fi.
  wifi,

  /// Reachable over mobile data.
  mobile,

  /// The platform could not report connectivity.
  unknown,
}

/// Coarse availability derived from the last successful communication
/// (SRS FR-015).
///
/// This is an observation about *reachability*, never a claim that a phone is
/// physically powered off.
enum DeviceAvailabilityState {
  /// Recently and reliably reachable.
  active,

  /// Seen within the last few minutes.
  recentlySeen,

  /// Not observed recently; last seen time must accompany this state.
  offline,

  /// Availability could not be determined.
  unknown,
}

/// The current observable state of a single device.
///
/// Every field is a [MetricValue], so the composite state automatically carries
/// per-metric provenance, availability and freshness. The SRS requires that a
/// device state be built from observations, not assumptions (SRS 1.4, FR-057).
class DeviceState {
  const DeviceState({
    required this.deviceId,
    required this.batteryPercentage,
    required this.chargingState,
    required this.chargingDuration,
    required this.networkStatus,
    required this.availability,
    required this.offlineDuration,
    required this.lastActivity,
    required this.generatedAt,
  });

  /// An "everything unknown" state used before real data is available.
  ///
  /// This is what the UI renders for a partner whose data has never been
  /// received; it shows Unknown rather than inventing values (FR-048).
  factory DeviceState.empty(String deviceId) {
    return DeviceState(
      deviceId: deviceId,
      batteryPercentage: const MetricValue<int>.unknown(),
      chargingState: const MetricValue<ChargingState>.unknown(),
      chargingDuration: const MetricValue<Duration>.unknown(),
      networkStatus: const MetricValue<NetworkStatus>.unknown(),
      availability: const MetricValue<DeviceAvailabilityState>.unknown(),
      offlineDuration: const MetricValue<Duration>.unknown(),
      lastActivity: const MetricValue<Duration>.unknown(),
      generatedAt: null,
    );
  }

  /// The device this state belongs to.
  final String deviceId;

  /// Battery level in the range 0–100 (FR-008).
  final MetricValue<int> batteryPercentage;

  /// Charging state (FR-009, FR-011).
  final MetricValue<ChargingState> chargingState;

  /// How long the device has been continuously observed as charging
  /// (FR-010). Derived from observed start/stop events, not guessed.
  final MetricValue<Duration> chargingDuration;

  /// Connectivity state (FR-012).
  final MetricValue<NetworkStatus> networkStatus;

  /// Reachability classification (FR-015).
  final MetricValue<DeviceAvailabilityState> availability;

  /// Approximate time since the device was last observed online
  /// (FR-013). Derived.
  final MetricValue<Duration> offlineDuration;

  /// Time since the most recent supported activity indication (FR-016,
  /// FR-017). Never implies continuous screen monitoring.
  final MetricValue<Duration> lastActivity;

  /// When this composite state snapshot was assembled, in UTC.
  final DateTime? generatedAt;

  @override
  String toString() => 'DeviceState(deviceId: $deviceId, at: $generatedAt)';
}
