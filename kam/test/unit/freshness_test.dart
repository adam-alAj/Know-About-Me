import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/time/clock.dart';
import 'package:kam/features/device_state/domain/models/metric_value.dart';

void main() {
  const policy = FreshnessPolicy(
    freshFor: Duration(seconds: 30),
    recentFor: Duration(minutes: 5),
  );
  final now = DateTime.utc(2026, 9, 26, 12);

  group('FreshnessPolicy', () {
    test('classifies fresh, recent and stale ages', () {
      expect(
        policy.classifyAge(const Duration(seconds: 5)),
        DataFreshness.fresh,
      );
      expect(
        policy.classifyAge(const Duration(minutes: 2)),
        DataFreshness.recent,
      );
      expect(policy.classifyAge(const Duration(hours: 2)), DataFreshness.stale);
    });

    test('a future timestamp is treated as fresh, not stale', () {
      expect(
        policy.classifyAge(const Duration(minutes: -3)),
        DataFreshness.fresh,
      );
    });
  });

  group('MetricValue freshness', () {
    test('reports the age and freshness relative to a clock', () {
      final clock = FixedClock(now);
      final value = MetricValue.observed(
        value: 42,
        observedAt: now.subtract(const Duration(seconds: 12)),
        source: 'test.battery',
        freshnessPolicy: policy,
      );

      expect(value.ageAt(clock.nowUtc()), const Duration(seconds: 12));
      expect(value.freshnessAt(clock.nowUtc()), DataFreshness.fresh);
    });

    test('a stale location is never presented as current', () {
      final clock = FixedClock(now);
      final value = MetricValue.observed(
        value: 'home',
        observedAt: now.subtract(const Duration(hours: 2, minutes: 13)),
        source: 'test.location',
        freshnessPolicy: FreshnessPolicy.slow,
      );

      expect(value.freshnessAt(clock.nowUtc()), DataFreshness.stale);
    });

    test('a value without a timestamp has unknown freshness', () {
      expect(
        const MetricValue<int>.unknown().freshnessAt(now),
        DataFreshness.unknown,
      );
    });
  });

  group('FixedClock', () {
    test('returns the fixed instant in UTC', () {
      expect(FixedClock(now).nowUtc(), now);
    });
  });
}
