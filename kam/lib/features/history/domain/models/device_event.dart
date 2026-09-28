/// Categories exposed by the history filter.
enum EventCategory { device, network, location, charging, rules, notifications }

/// A controlled vocabulary of meaningful events. Raw samples are never events.
enum DeviceEventType {
  chargingStarted,
  chargingStopped,
  deviceWentOffline,
  deviceCameOnline,
  locationChangedSignificantly,
  ruleActivated,
  ruleDeactivated,
  ruleBecameUnknown,
  ruleNotificationGenerated,
  connectionChanged,
  sharingPermissionChanged,
  interpretationGenerated,
  notificationSuppressed,
}

extension DeviceEventTypeCategory on DeviceEventType {
  EventCategory get category => switch (this) {
    DeviceEventType.chargingStarted || DeviceEventType.chargingStopped => EventCategory.charging,
    DeviceEventType.deviceWentOffline || DeviceEventType.deviceCameOnline || DeviceEventType.connectionChanged => EventCategory.network,
    DeviceEventType.locationChangedSignificantly => EventCategory.location,
    DeviceEventType.ruleActivated || DeviceEventType.ruleDeactivated || DeviceEventType.ruleBecameUnknown || DeviceEventType.interpretationGenerated => EventCategory.rules,
    DeviceEventType.ruleNotificationGenerated || DeviceEventType.notificationSuppressed => EventCategory.notifications,
    DeviceEventType.sharingPermissionChanged => EventCategory.device,
  };
}

/// A normalized, privacy-minimized historical event.
///
/// [id] is deterministic for a logical transition. [occurredAt] is the
/// observation/evaluation time; [recordedAt] is assigned by Firestore on sync.
class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.pairId,
    this.deviceId = '',
    required this.type,
    required this.occurredAt,
    this.ownerUserId,
    this.recordedAt,
    this.observedAt,
    this.source = 'device',
    this.deduplicationKey,
    this.summary,
    this.payload = const <String, Object?>{},
    this.schemaVersion = 1,
  });

  final String id;
  final String pairId;
  /// Local opaque device reference; omitted from remote history.
  final String deviceId;
  final String? ownerUserId;
  final DeviceEventType type;
  final DateTime occurredAt;
  final DateTime? recordedAt;
  final DateTime? observedAt;
  final String source;
  final String? deduplicationKey;
  final String? summary;
  final Map<String, Object?> payload;
  final int schemaVersion;
  EventCategory get category => type.category;

  Map<String, Object?> toJson({bool includeRecordedAt = true}) => {
    'id': id,
    'pairId': pairId,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
    if (ownerUserId != null) 'ownerUserId': ownerUserId,
    'type': type.name,
    'category': category.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (includeRecordedAt && recordedAt != null) 'recordedAt': recordedAt!.toUtc().toIso8601String(),
    if (observedAt != null) 'observedAt': observedAt!.toUtc().toIso8601String(),
    'source': source,
    if (deduplicationKey != null) 'deduplicationKey': deduplicationKey,
    if (summary != null) 'summary': summary,
    if (payload.isNotEmpty) 'payload': payload,
    'schemaVersion': schemaVersion,
  };

  factory DeviceEvent.fromJson(Map<String, Object?> json) {
    final type = DeviceEventType.values.byName(json['type']! as String);
    final category = EventCategory.values.byName(json['category']! as String);
    if (type.category != category) throw const FormatException('Event category does not match type.');
    final occurredAt = DateTime.tryParse(json['occurredAt'] as String? ?? '');
    if (occurredAt == null) throw const FormatException('Invalid event time.');
    DateTime? parseTime(Object? value) => value == null ? null : DateTime.tryParse(value as String)?.toUtc();
    return DeviceEvent(
      id: json['id']! as String,
      pairId: json['pairId']! as String,
      deviceId: json['deviceId'] as String? ?? '',
      ownerUserId: json['ownerUserId'] as String?,
      type: type,
      occurredAt: occurredAt.toUtc(),
      recordedAt: parseTime(json['recordedAt']),
      observedAt: parseTime(json['observedAt']),
      source: json['source'] as String? ?? 'device',
      deduplicationKey: json['deduplicationKey'] as String?,
      summary: json['summary'] as String?,
      payload: json['payload'] == null ? const <String, Object?>{} : Map<String, Object?>.from(json['payload']! as Map),
      schemaVersion: json['schemaVersion'] as int? ?? 1,
    );
  }

  @override
  String toString() => 'DeviceEvent($id, ${type.name}, $occurredAt)';
}
