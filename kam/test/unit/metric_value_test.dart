import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/data/data_availability.dart';
import 'package:kam/features/device_state/domain/models/device_state.dart';
import 'package:kam/features/device_state/domain/models/metric_value.dart';

void main() {
  final observedAt = DateTime.utc(2026, 9, 26, 12);

  group('MetricValue origins', () {
    test('observed values are measurable facts', () {
      final value = MetricValue.observed(
        value: 82,
        observedAt: observedAt,
        source: 'test.battery',
      );

      expect(value.origin, ValueOrigin.observed);
      expect(value.isInterpretation, isFalse);
      expect(value.hasValue, isTrue);
      expect(value.value, 82);
    });

    test('derived values are computed from observations', () {
      final value = MetricValue.derived(
        value: const Duration(hours: 4, minutes: 8),
        observedAt: observedAt,
        source: 'test.charging',
      );

      expect(value.origin, ValueOrigin.derived);
      expect(value.isInterpretation, isFalse);
    });

    test('interpretations are never treated as measurements', () {
      final value = MetricValue.interpretation(
        value: 70,
        observedAt: observedAt,
        source: 'user.rule',
      );

      expect(value.origin, ValueOrigin.interpretation);
      expect(value.isInterpretation, isTrue);
    });
  });

  group('MetricValue availability', () {
    test('unknown, unsupported, unavailable and paused carry no value', () {
      expect(const MetricValue<int>.unknown().hasValue, isFalse);
      expect(
        const MetricValue<int>.unknown().availability,
        DataAvailability.unknown,
      );
      expect(
        const MetricValue<int>.unsupported().availability,
        DataAvailability.unsupported,
      );
      expect(
        const MetricValue<int>.unavailable().availability,
        DataAvailability.unavailable,
      );
      expect(
        const MetricValue<int>.paused().availability,
        DataAvailability.paused,
      );
    });

    test('a revoked permission keeps provenance but drops the live value', () {
      final observed = MetricValue.observed(
        value: 0.4,
        observedAt: observedAt,
        source: 'test.location',
      );

      final unavailable = observed.asUnavailable();

      expect(unavailable.availability, DataAvailability.unavailable);
      expect(unavailable.hasValue, isFalse);
      // Provenance is retained for audit only.
      expect(unavailable.observedAt, observedAt);
      expect(unavailable.source, 'test.location');
    });
  });

  group('DeviceState', () {
    test('empty state is entirely unknown rather than fabricated', () {
      final state = DeviceState.empty('device-1');

      expect(state.batteryPercentage.availability, DataAvailability.unknown);
      expect(state.chargingState.availability, DataAvailability.unknown);
      expect(state.networkStatus.availability, DataAvailability.unknown);
      // There is intentionally no "powered off" availability anywhere.
      expect(state.availability.availability, DataAvailability.unknown);
    });
  });
}
