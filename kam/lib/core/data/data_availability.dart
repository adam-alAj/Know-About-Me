/// Whether a piece of data can currently be communicated at all.
///
/// Lives in `core/` because it is consumed by device state, location, sharing
/// and UI presentation alike. Moved here in Phase 2 from
/// `features/device_state/domain/models/metric_value.dart` (the enum is
/// unchanged) so that `core/ui` can depend on it without depending on a feature.
///
/// SRS FR-048, FR-056, FR-068 and NFR-015 require the application to represent
/// an unavailable metric explicitly instead of fabricating a value.
enum DataAvailability {
  /// A value is present and may be displayed.
  available,

  /// The metric is supported but the current value could not be determined.
  unknown,

  /// The device or operating system cannot provide this metric at all.
  unsupported,

  /// The metric is normally supported but is currently not accessible, for
  /// example because an OS permission is missing (FR-056).
  unavailable,

  /// The owner has explicitly paused sharing of this metric (FR-053).
  paused,
}
