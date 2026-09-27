import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/location/domain/models/location_state.dart';
import 'package:kam/features/location/domain/services/geo_distance.dart';

void main() {
  const geo = GeoDistance();

  test('identical coordinates are zero metres apart', () {
    const point = Coordinate(latitude: 31.9038, longitude: 35.2034);
    expect(geo.metersBetween(point, point), 0);
  });

  test('one degree of latitude is about 111 km anywhere', () {
    final distance = geo.metersBetween(
      const Coordinate(latitude: 0, longitude: 0),
      const Coordinate(latitude: 1, longitude: 0),
    );
    expect(distance, closeTo(111195, 150));
  });

  test('one degree of longitude at the equator is about 111 km', () {
    final distance = geo.metersBetween(
      const Coordinate(latitude: 0, longitude: 0),
      const Coordinate(latitude: 0, longitude: 1),
    );
    expect(distance, closeTo(111195, 150));
  });

  test('longitude shrinks with latitude, which naive maths would miss', () {
    final atEquator = geo.metersBetween(
      const Coordinate(latitude: 0, longitude: 0),
      const Coordinate(latitude: 0, longitude: 1),
    )!;
    final atSixty = geo.metersBetween(
      const Coordinate(latitude: 60, longitude: 0),
      const Coordinate(latitude: 60, longitude: 1),
    )!;
    // cos(60°) = 0.5, so the same longitude delta is roughly half the distance.
    expect(atSixty / atEquator, closeTo(0.5, 0.01));
  });

  test('a known city pair is within the expected range', () {
    // Jerusalem to Tel Aviv is about 54 km as the crow flies.
    final distance = geo.metersBetween(
      const Coordinate(latitude: 31.7683, longitude: 35.2137),
      const Coordinate(latitude: 32.0853, longitude: 34.7818),
    );
    expect(distance, closeTo(53900, 2000));
  });

  test('nearby points resolve to metres, not zero', () {
    final distance = geo.metersBetween(
      const Coordinate(latitude: 31.9038, longitude: 35.2034),
      const Coordinate(latitude: 31.9040, longitude: 35.2034),
    );
    expect(distance, greaterThan(20));
    expect(distance, lessThan(25));
  });

  test('distance is symmetric', () {
    const a = Coordinate(latitude: 48.8566, longitude: 2.3522);
    const b = Coordinate(latitude: 52.52, longitude: 13.405);
    expect(geo.metersBetween(a, b), geo.metersBetween(b, a));
  });

  test('invalid coordinates yield null instead of a guessed distance', () {
    const valid = Coordinate(latitude: 31.9038, longitude: 35.2034);
    for (final invalid in [
      const Coordinate(latitude: 91, longitude: 0),
      const Coordinate(latitude: -90.1, longitude: 0),
      const Coordinate(latitude: 0, longitude: 181),
      const Coordinate(latitude: double.nan, longitude: double.infinity),
    ]) {
      expect(invalid.isValid, isFalse);
      expect(geo.metersBetween(valid, invalid), isNull);
      expect(geo.metersBetween(invalid, valid), isNull);
    }
  });
}
