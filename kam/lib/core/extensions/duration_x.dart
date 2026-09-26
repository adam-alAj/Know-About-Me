/// Human-readable formatting for [Duration].
///
/// Extracted in Phase 2 so that charging duration, offline duration, location
/// age and rule durations are all rendered the same way (SRS NFR-021, NFR-025).
extension DurationX on Duration {
  /// Compact form, for example `2h 18m`, `4h 08m`, `47m`, `12s`.
  String get compact {
    final totalSeconds = inSeconds.abs();
    if (totalSeconds < 60) return '${totalSeconds}s';

    // Derived from the absolute second count so negative durations format the
    // same way as positive ones.
    final days = totalSeconds ~/ Duration.secondsPerDay;
    final hours =
        (totalSeconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
    final minutes =
        (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;

    if (days > 0) {
      return minutes > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m';
  }

  /// Long form, for example `2 hours 18 minutes`, `47 minutes`.
  String get humanReadable {
    final totalSeconds = inSeconds.abs();
    if (totalSeconds < 60) return '$totalSeconds seconds';

    final days = totalSeconds ~/ Duration.secondsPerDay;
    final hours =
        (totalSeconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
    final minutes =
        (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;

    final parts = <String>[];
    if (days > 0) parts.add(_plural(days, 'day'));
    if (hours > 0) parts.add(_plural(hours, 'hour'));
    if (minutes > 0) parts.add(_plural(minutes, 'minute'));
    return parts.isEmpty ? 'less than a minute' : parts.join(' ');
  }

  static String _plural(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'}';
}
