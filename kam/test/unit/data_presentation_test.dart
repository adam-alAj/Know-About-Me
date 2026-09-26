import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/data/data_availability.dart';
import 'package:kam/core/freshness/data_freshness.dart';
import 'package:kam/core/ui/data_presentation_state.dart';

void main() {
  group('DataPresentation.fromAvailability', () {
    test('available data with a value becomes loaded', () {
      final presentation = DataPresentation.fromAvailability(
        DataAvailability.available,
        freshness: DataFreshness.fresh,
        age: const Duration(seconds: 12),
      );

      expect(presentation.state, DataPresentationState.loaded);
      expect(presentation.hasContent, isTrue);
      expect(presentation.showsFreshness, isTrue);
    });

    test('available but valueless data becomes empty', () {
      final presentation = DataPresentation.fromAvailability(
        DataAvailability.available,
        hasValue: false,
      );

      expect(presentation.state, DataPresentationState.empty);
      expect(presentation.hasContent, isFalse);
    });

    test('maps each non-available state explicitly', () {
      expect(
        DataPresentation.fromAvailability(DataAvailability.unknown).state,
        DataPresentationState.unknown,
      );
      expect(
        DataPresentation.fromAvailability(DataAvailability.unsupported).state,
        DataPresentationState.unsupported,
      );
      expect(
        DataPresentation.fromAvailability(DataAvailability.unavailable).state,
        DataPresentationState.unavailable,
      );
      expect(
        DataPresentation.fromAvailability(DataAvailability.paused).state,
        DataPresentationState.paused,
      );
    });

    test('non-available states are never treated as content', () {
      for (final availability in [
        DataAvailability.unknown,
        DataAvailability.unsupported,
        DataAvailability.unavailable,
        DataAvailability.paused,
      ]) {
        final presentation = DataPresentation.fromAvailability(availability);
        expect(presentation.hasContent, isFalse);
        expect(presentation.isUnavailable, isTrue);
      }
    });
  });

  group('DataPresentation states', () {
    test('loading and failure carry no freshness', () {
      expect(const DataPresentation.loading().showsFreshness, isFalse);
      expect(
        const DataPresentation.failure('Please try again').message,
        'Please try again',
      );
    });

    test('loaded without freshness does not show a freshness caption', () {
      expect(const DataPresentation.loaded().showsFreshness, isFalse);
    });
  });
}
