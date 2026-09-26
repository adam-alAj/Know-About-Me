import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/time/date_time_utils.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26, 12);

  group('DateTimeUtils.formatAge', () {
    test('treats very recent timestamps as "just now"', () {
      expect(DateTimeUtils.formatAge(const Duration(seconds: 3)), 'just now');
    });

    test('renders seconds, minutes and hours', () {
      expect(
        DateTimeUtils.formatAge(const Duration(seconds: 30)),
        '30 seconds ago',
      );
      expect(DateTimeUtils.formatAge(const Duration(minutes: 2)), '2m ago');
      expect(
        DateTimeUtils.formatAge(const Duration(hours: 2, minutes: 13)),
        '2h 13m ago',
      );
    });

    test('handles a future timestamp without a negative age', () {
      expect(DateTimeUtils.formatAge(const Duration(minutes: -5)), 'just now');
    });
  });

  group('DateTimeUtils.formatAgeSince', () {
    test('computes the age relative to the supplied now', () {
      expect(
        DateTimeUtils.formatAgeSince(
          now.subtract(const Duration(minutes: 30)),
          now,
        ),
        '30m ago',
      );
    });
  });

  group('DateTimeUtils.formatLocalTimestamp', () {
    test('produces a non-empty localised timestamp', () {
      final formatted = DateTimeUtils.formatLocalTimestamp(now);

      expect(formatted, isNotEmpty);
      expect(formatted, contains('2026'));
    });

    test('normalises any DateTime to UTC', () {
      final local = DateTime(2026, 9, 26, 12);
      expect(DateTimeUtils.toUtc(local).isUtc, isTrue);
    });
  });
}
