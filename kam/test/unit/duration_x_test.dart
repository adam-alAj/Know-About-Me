import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/extensions/duration_x.dart';

void main() {
  group('DurationX.compact', () {
    test('formats seconds, minutes, hours and days', () {
      expect(const Duration(seconds: 12).compact, '12s');
      expect(const Duration(minutes: 47).compact, '47m');
      expect(const Duration(hours: 4, minutes: 8).compact, '4h 08m');
      expect(const Duration(days: 2).compact, '2d');
      expect(const Duration(days: 2, hours: 3, minutes: 5).compact, '2d 3h');
    });

    test('ignores the sign so ages render consistently', () {
      expect(const Duration(minutes: -47).compact, '47m');
    });
  });

  group('DurationX.humanReadable', () {
    test('formats with correct pluralisation', () {
      expect(const Duration(seconds: 30).humanReadable, '30 seconds');
      expect(const Duration(minutes: 1).humanReadable, '1 minute');
      expect(
        const Duration(hours: 4, minutes: 8).humanReadable,
        '4 hours 8 minutes',
      );
      expect(
        const Duration(days: 1, hours: 1, minutes: 1).humanReadable,
        '1 day 1 hour 1 minute',
      );
    });
  });
}
