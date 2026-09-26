/// Time abstraction for the application.
///
/// Time is injected rather than read directly from [DateTime.now] so that
/// freshness calculations (NFR-025) and rule evaluation (NFR-033) are
/// deterministic and unit-testable.
abstract interface class Clock {
  /// Returns the current instant in UTC.
  ///
  /// All timestamps stored or compared by the application are UTC. Conversion
  /// to the user's local time zone happens only at the presentation layer
  /// (NFR-026).
  DateTime nowUtc();
}

/// Production [Clock] backed by the platform clock.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A [Clock] that returns a fixed instant.
///
/// Intended for tests and local previews only.
class FixedClock implements Clock {
  FixedClock(this._instant);

  final DateTime _instant;

  @override
  DateTime nowUtc() => _instant.toUtc();
}
