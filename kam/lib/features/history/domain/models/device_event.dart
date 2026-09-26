/// Categories used to filter history (SRS FR-051).
enum EventCategory { device, network, location, charging, rules, notifications }

/// Types of historical event the application records (SRS FR-049).
enum DeviceEventType {
  chargingStarted,
  chargingStopped,
  deviceWentOffline,
  deviceCameOnline,
  locationChangedSignificantly,
  ruleActivated,
  ruleNotificationGenerated,
  connectionChanged,
  sharingPermissionChanged,
}

extension DeviceEventTypeCategory on DeviceEventType {
  /// The history category this event belongs to (FR-051).
  EventCategory get category {
    switch (this) {
      case DeviceEventType.chargingStarted:
      case DeviceEventType.chargingStopped:
        return EventCategory.charging;
      case DeviceEventType.deviceWentOffline:
      case DeviceEventType.deviceCameOnline:
        return EventCategory.network;
      case DeviceEventType.locationChangedSignificantly:
        return EventCategory.location;
      case DeviceEventType.ruleActivated:
        return EventCategory.rules;
      case DeviceEventType.ruleNotificationGenerated:
        return EventCategory.notifications;
      case DeviceEventType.connectionChanged:
      case DeviceEventType.sharingPermissionChanged:
        return EventCategory.device;
    }
  }
}

/// A meaningful state change or rule event stored for history (SRS FR-049,
/// FR-050, FR-058).
///
/// The system intentionally stores meaningful events plus current state rather
/// than high-frequency raw telemetry (SRS FR-058, NFR-039).
class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.pairId,
    required this.deviceId,
    required this.type,
    required this.occurredAt,
    this.recordedAt,
    this.summary,
  });

  final String id;
  final String pairId;
  final String deviceId;
  final DeviceEventType type;

  /// When the event happened on the device, in UTC (FR-050).
  final DateTime occurredAt;

  /// When the server recorded the event, in UTC (NFR-026).
  final DateTime? recordedAt;

  /// Optional concise human-readable summary that avoids private detail.
  final String? summary;

  /// History category of this event (FR-051).
  EventCategory get category => type.category;

  @override
  String toString() => 'DeviceEvent($id, ${type.name}, $occurredAt)';
}
