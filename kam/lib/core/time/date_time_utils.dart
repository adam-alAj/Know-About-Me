import 'package:intl/intl.dart';

import '../extensions/duration_x.dart';

/// Shared time helpers.
///
/// Policy (SRS NFR-026): persisted and exchanged timestamps are always UTC;
/// conversion to the user's local time zone happens **only** here, at the point
/// of display. Business logic must never call `DateTime.now()` directly — it
/// takes a `Clock` from `core/time/clock.dart`.
abstract final class DateTimeUtils {
  /// Normalises any [DateTime] to UTC.
  static DateTime toUtc(DateTime value) => value.toUtc();

  /// Formats a UTC instant in the device's local time zone, for example
  /// `9/26/2026, 8:42 PM`.
  static String formatLocalTimestamp(DateTime utc, {String? locale}) {
    final formatter = DateFormat.yMd(locale).add_Hm();
    return formatter.format(utc.toLocal());
  }

  /// Renders an age as a relative phrase, for example `12 seconds ago`,
  /// `4h 08m ago`.
  ///
  /// Used by the freshness indicator so a stale value is visibly stale rather
  /// than silently current (FR-047, NFR-025).
  static String formatAge(Duration age) {
    if (age.isNegative) return 'just now';
    final seconds = age.inSeconds;
    if (seconds < 45) {
      return seconds <= 5 ? 'just now' : '$seconds seconds ago';
    }
    return '${age.compact} ago';
  }

  /// Renders the age of [observedAt] relative to [now].
  static String formatAgeSince(DateTime observedAt, DateTime now) =>
      formatAge(now.toUtc().difference(observedAt.toUtc()));
}
