import '../../../../core/freshness/data_freshness.dart';
import 'state_observation.dart';

/// Evidence that this device/application recently produced a valid observable
/// signal (Phase 9).
///
/// Availability is deliberately **evidence-based**: it answers "has a valid
/// local signal been observed recently?", never "is the phone powered on?".
/// There is no `phonePoweredOff` state anywhere in the model — a lack of
/// recent activity, network connectivity or Firebase synchronization is not
/// proof of power state (SRS FR-015, FR-070).
///
/// The states map onto [CapabilityAvailability]:
/// * `available` — positive evidence exists within the freshness window.
/// * `stale` — evidence exists but is too old to treat as current;
///   [lastConfirmedAvailableAt] keeps the historical time.
/// * `unknown` — no positive evidence and no structural reason.
/// * `unsupported` / `permissionDenied` / `error` / `unavailable` — the
///   underlying observations report that reason.
class DeviceAvailabilityEvidence {
  const DeviceAvailabilityEvidence({
    required this.availability,
    required this.observedAt,
    this.lastConfirmedAvailableAt,
    this.source,
    this.error,
  });

  /// No evidence has ever been gathered.
  const DeviceAvailabilityEvidence.unknown()
    : availability = CapabilityAvailability.unknown,
      lastConfirmedAvailableAt = null,
      observedAt = null,
      source = null,
      error = null;

  /// Why availability currently looks the way it does.
  final CapabilityAvailability availability;

  /// Newest timestamp that positively confirmed availability, `null` when no
  /// positive evidence exists. A restored historical timestamp keeps its real
  /// time; it is never re-stamped to "now".
  final DateTime? lastConfirmedAvailableAt;

  /// When this assessment was derived, in UTC.
  final DateTime? observedAt;

  /// Where the evidence came from, for example `local_observations`.
  final String? source;

  /// Diagnostic detail when [availability] is [CapabilityAvailability.error].
  final String? error;

  /// Freshness of the *evidence* at [now]: how current the newest positive
  /// signal is, not when the assessment was computed.
  DataFreshness freshnessAt(DateTime now) {
    final confirmed = lastConfirmedAvailableAt;
    if (confirmed == null) return DataFreshness.unknown;
    return FreshnessPolicy.standard.classifyAge(
      now.toUtc().difference(confirmed.toUtc()),
    );
  }

  Map<String, Object?> toJson() => {
    'availability': availability.name,
    'lastConfirmedAvailableAt': lastConfirmedAvailableAt
        ?.toUtc()
        .toIso8601String(),
    'observedAt': observedAt?.toUtc().toIso8601String(),
    'source': source,
    'error': error,
  };

  factory DeviceAvailabilityEvidence.fromJson(Map<String, Object?> json) =>
      DeviceAvailabilityEvidence(
        availability: CapabilityAvailability.values.byName(
          json['availability']! as String,
        ),
        lastConfirmedAvailableAt: _date(json['lastConfirmedAvailableAt']),
        observedAt: _date(json['observedAt']),
        source: json['source'] as String?,
        error: json['error'] as String?,
      );

  static DateTime? _date(Object? value) => value == null
      ? null
      : DateTime.parse(value as String).toUtc();

  @override
  String toString() =>
      'DeviceAvailabilityEvidence(${availability.name}, '
      'confirmed: $lastConfirmedAvailableAt)';
}
