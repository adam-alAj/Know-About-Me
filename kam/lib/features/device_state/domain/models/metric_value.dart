import '../../../../core/data/data_availability.dart';
import '../../../../core/freshness/data_freshness.dart';

/// Where a value came from.
///
/// This distinction is the core of SRS FR-030, NFR-023 and NFR-041: the
/// application must never present a user-configured interpretation as an
/// objectively measured fact.
enum ValueOrigin {
  /// Directly measured on a device (for example `battery = 82%`).
  observed,

  /// Computed deterministically from observed values (for example
  /// `charging duration = 4h 12m`, or `offline duration`).
  derived,

  /// Produced by a user-defined rule (for example `sleep probability = 70%`).
  ///
  /// Never a measurement and never an objectively validated probability.
  interpretation,
}

/// An immutable, self-describing measurement of a single device metric.
///
/// A [MetricValue] always carries where the value came from, whether it is
/// available, when it was observed, and how fresh it is. This satisfies
/// SRS FR-047 and Task 11's requirement that every remotely observed state
/// conceptually supports value, timestamp, source, availability, freshness and
/// optional quality metadata.
class MetricValue<T> {
  const MetricValue._({
    required this.origin,
    required this.availability,
    required this.freshnessPolicy,
    this.value,
    this.observedAt,
    this.source,
    this.accuracyNote,
  });

  /// Creates an observed metric measured directly on a device.
  factory MetricValue.observed({
    required T value,
    required DateTime observedAt,
    required String source,
    FreshnessPolicy freshnessPolicy = FreshnessPolicy.standard,
    String? accuracyNote,
  }) {
    return MetricValue<T>._(
      origin: ValueOrigin.observed,
      availability: DataAvailability.available,
      freshnessPolicy: freshnessPolicy,
      value: value,
      observedAt: observedAt,
      source: source,
      accuracyNote: accuracyNote,
    );
  }

  /// Creates a value derived deterministically from observed values.
  factory MetricValue.derived({
    required T value,
    required DateTime observedAt,
    required String source,
    FreshnessPolicy freshnessPolicy = FreshnessPolicy.standard,
    String? accuracyNote,
  }) {
    return MetricValue<T>._(
      origin: ValueOrigin.derived,
      availability: DataAvailability.available,
      freshnessPolicy: freshnessPolicy,
      value: value,
      observedAt: observedAt,
      source: source,
      accuracyNote: accuracyNote,
    );
  }

  /// Creates an interpretation produced by a user-defined rule.
  ///
  /// The [value] is the user's configured outcome, not a scientific result.
  /// Prefer the richer `Interpretation` domain model for rule output; this
  /// factory exists for metrics expressed as a plain scalar.
  factory MetricValue.interpretation({
    required T value,
    required DateTime observedAt,
    required String source,
    FreshnessPolicy freshnessPolicy = FreshnessPolicy.standard,
    String? accuracyNote,
  }) {
    return MetricValue<T>._(
      origin: ValueOrigin.interpretation,
      availability: DataAvailability.available,
      freshnessPolicy: freshnessPolicy,
      value: value,
      observedAt: observedAt,
      source: source,
      accuracyNote: accuracyNote,
    );
  }

  /// The metric is supported but no value could be determined.
  const MetricValue.unknown({
    this.freshnessPolicy = FreshnessPolicy.standard,
    this.source,
    this.observedAt,
  }) : origin = ValueOrigin.observed,
       availability = DataAvailability.unknown,
       value = null,
       accuracyNote = null;

  /// The device or platform cannot provide this metric.
  const MetricValue.unsupported({
    this.freshnessPolicy = FreshnessPolicy.standard,
    this.source,
  }) : origin = ValueOrigin.observed,
       availability = DataAvailability.unsupported,
       value = null,
       observedAt = null,
       accuracyNote = null;

  /// The metric is temporarily inaccessible (for example a revoked permission).
  const MetricValue.unavailable({
    this.freshnessPolicy = FreshnessPolicy.standard,
    this.source,
    this.observedAt,
  }) : origin = ValueOrigin.observed,
       availability = DataAvailability.unavailable,
       value = null,
       accuracyNote = null;

  /// The owner has paused sharing of this metric.
  const MetricValue.paused({
    this.freshnessPolicy = FreshnessPolicy.standard,
    this.source,
  }) : origin = ValueOrigin.observed,
       availability = DataAvailability.paused,
       value = null,
       observedAt = null,
       accuracyNote = null;

  /// The measured or configured value, or `null` when unavailable.
  final T? value;

  /// Where the value came from.
  final ValueOrigin origin;

  /// Whether the metric can currently be communicated.
  final DataAvailability availability;

  /// When the underlying observation happened, in UTC.
  final DateTime? observedAt;

  /// A short technical identifier of the producer, for example
  /// `android.battery_manager`.
  final String? source;

  /// Optional human-readable quality note, for example
  /// `Approximate (accuracy ~1200 m)`.
  final String? accuracyNote;

  /// Policy used to classify the age of this value.
  final FreshnessPolicy freshnessPolicy;

  /// Whether a displayable value exists.
  bool get hasValue =>
      availability == DataAvailability.available && value != null;

  /// Whether the value is a user-rule interpretation rather than a measurement.
  bool get isInterpretation => origin == ValueOrigin.interpretation;

  /// Age of the value at [now], or `null` when no timestamp is known.
  Duration? ageAt(DateTime now) {
    final observed = observedAt;
    if (observed == null) return null;
    return now.toUtc().difference(observed.toUtc());
  }

  /// Freshness of the value at [now].
  DataFreshness freshnessAt(DateTime now) {
    final age = ageAt(now);
    if (age == null) return DataFreshness.unknown;
    return freshnessPolicy.classifyAge(age);
  }

  /// Returns a copy marked unavailable while keeping provenance for audit.
  ///
  /// Used when a permission is revoked: the last value is retained but must no
  /// longer be presented as current (FR-056, NFR-037).
  MetricValue<T> asUnavailable() => MetricValue<T>._(
    origin: origin,
    availability: DataAvailability.unavailable,
    freshnessPolicy: freshnessPolicy,
    value: value,
    observedAt: observedAt,
    source: source,
    accuracyNote: accuracyNote,
  );

  /// Returns a copy marked as paused by the owner (FR-053).
  MetricValue<T> asPaused() => MetricValue<T>._(
    origin: origin,
    availability: DataAvailability.paused,
    freshnessPolicy: freshnessPolicy,
    value: value,
    observedAt: observedAt,
    source: source,
    accuracyNote: accuracyNote,
  );

  @override
  String toString() {
    return 'MetricValue<$T>(origin: ${origin.name}, '
        'availability: ${availability.name}, value: $value, '
        'observedAt: $observedAt, source: $source)';
  }
}
