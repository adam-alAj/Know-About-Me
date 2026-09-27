/// Freshness semantics for remotely observed device data.
///
/// Implements SRS FR-047, FR-061, NFR-007 and NFR-025: a value that was not
/// updated recently must not look indistinguishable from a freshly observed
/// value, and stale data must never be presented as current.
library;

/// How current a piece of data is, relative to a [FreshnessPolicy].
enum DataFreshness {
  /// Observed within the policy's `freshFor` window.
  fresh,

  /// Observed within the policy's `recentFor` window but no longer fresh.
  recent,

  /// Older than the policy's `recentFor` window.
  stale,

  /// No observation timestamp is available, so freshness cannot be classified.
  unknown,
}

/// Thresholds used to classify the age of a value.
///
/// Policies are per-metric because different metrics change at very different
/// rates: a battery level is meaningful for a few minutes, while a last-known
/// location may remain useful for much longer before it is stale.
class FreshnessPolicy {
  const FreshnessPolicy({required this.freshFor, required this.recentFor});

  /// Age at or below which a value is considered [DataFreshness.fresh].
  final Duration freshFor;

  /// Age at or below which a value is considered [DataFreshness.recent].
  final Duration recentFor;

  /// A sensible default for metrics that are expected to update frequently.
  static const FreshnessPolicy standard = FreshnessPolicy(
    freshFor: Duration(minutes: 2),
    recentFor: Duration(minutes: 15),
  );

  /// A slower policy for metrics that legitimately update infrequently.
  static const FreshnessPolicy slow = FreshnessPolicy(
    freshFor: Duration(minutes: 15),
    recentFor: Duration(hours: 2),
  );

  /// Policy for location fixes (Phase 10).
  ///
  /// A fix a couple of minutes old is still a current position, while one
  /// older than half an hour must not be presented as current: the at-home /
  /// away classification becomes `stale` at that point.
  static const FreshnessPolicy location = FreshnessPolicy(
    freshFor: Duration(minutes: 5),
    recentFor: Duration(minutes: 30),
  );

  /// Classifies [age] according to this policy.
  DataFreshness classifyAge(Duration age) {
    if (age.isNegative) {
      // A timestamp in the future indicates clock skew; treat it as fresh
      // rather than pretending it is stale. The value itself is still shown.
      return DataFreshness.fresh;
    }
    if (age <= freshFor) return DataFreshness.fresh;
    if (age <= recentFor) return DataFreshness.recent;
    return DataFreshness.stale;
  }
}
