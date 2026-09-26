import '../data/data_availability.dart';
import '../freshness/data_freshness.dart';

/// The states the UI must be able to render for any piece of data.
///
/// This is the single vocabulary shared by loading, error, empty and the
/// device-data availability states, so a screen can never accidentally render
/// "0%" where the truth is "unknown" (SRS FR-048, NFR-006, NFR-015).
enum DataPresentationState {
  /// Data is being fetched.
  loading,

  /// A successful result that legitimately contains nothing (for example no
  /// rules configured yet).
  empty,

  /// A real value exists and may be shown.
  loaded,

  /// The operation failed; [DataPresentation.message] explains why, safely.
  failure,

  /// The metric is supported but the value could not be determined.
  unknown,

  /// The platform/device cannot provide this metric at all.
  unsupported,

  /// The metric is temporarily inaccessible (for example a revoked permission).
  unavailable,

  /// The owner paused sharing of this metric.
  paused,
}

/// A resolved presentation state plus the freshness metadata needed to show it
/// honestly.
class DataPresentation {
  /// Data is loading.
  const DataPresentation.loading()
    : state = DataPresentationState.loading,
      freshness = null,
      age = null,
      message = null;

  /// A successful but empty result.
  const DataPresentation.empty()
    : state = DataPresentationState.empty,
      freshness = null,
      age = null,
      message = null;

  /// A failed result. [message] must be safe to display.
  const DataPresentation.failure(this.message)
    : state = DataPresentationState.failure,
      freshness = null,
      age = null;

  /// A real value, optionally with freshness metadata.
  const DataPresentation.loaded({this.freshness, this.age})
    : state = DataPresentationState.loaded,
      message = null;

  /// The metric could not be determined.
  const DataPresentation.unknown()
    : state = DataPresentationState.unknown,
      freshness = null,
      age = null,
      message = null;

  /// The platform cannot provide the metric (FR-068).
  const DataPresentation.unsupported()
    : state = DataPresentationState.unsupported,
      freshness = null,
      age = null,
      message = null;

  /// The metric is temporarily inaccessible (FR-056).
  const DataPresentation.unavailable()
    : state = DataPresentationState.unavailable,
      freshness = null,
      age = null,
      message = null;

  /// The owner paused sharing (FR-053).
  const DataPresentation.paused()
    : state = DataPresentationState.paused,
      freshness = null,
      age = null,
      message = null;

  /// Derives a presentation from a domain availability flag.
  ///
  /// [hasValue] distinguishes "loaded" from "empty" for available data.
  factory DataPresentation.fromAvailability(
    DataAvailability availability, {
    DataFreshness? freshness,
    Duration? age,
    bool hasValue = true,
  }) {
    return switch (availability) {
      DataAvailability.available =>
        hasValue
            ? DataPresentation.loaded(freshness: freshness, age: age)
            : const DataPresentation.empty(),
      DataAvailability.unknown => const DataPresentation.unknown(),
      DataAvailability.unsupported => const DataPresentation.unsupported(),
      DataAvailability.unavailable => const DataPresentation.unavailable(),
      DataAvailability.paused => const DataPresentation.paused(),
    };
  }

  /// Which state to render.
  final DataPresentationState state;

  /// Freshness of the loaded value, when known.
  final DataFreshness? freshness;

  /// Age of the loaded value, when known.
  final Duration? age;

  /// User-safe explanation, only set for [DataPresentationState.failure].
  final String? message;

  /// Whether a real value should be rendered.
  bool get hasContent => state == DataPresentationState.loaded;

  /// Whether the state is a non-available device-data state.
  bool get isUnavailable =>
      state == DataPresentationState.unknown ||
      state == DataPresentationState.unsupported ||
      state == DataPresentationState.unavailable ||
      state == DataPresentationState.paused;

  /// Whether freshness metadata should be shown alongside the content.
  bool get showsFreshness => hasContent && freshness != null;

  @override
  String toString() =>
      'DataPresentation(${state.name}, freshness: ${freshness?.name})';
}
