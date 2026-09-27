import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/location/domain/models/location_state.dart';
import 'package:kam/features/location/domain/services/geo_distance.dart';
import 'package:kam/features/location/domain/services/home_presence_calculator.dart';

void main() {
  const calculator = HomePresenceCalculator();

  // A home whose radius is exactly 200 m (the SRS example).
  const home = HomeLocation(
    coordinate: Coordinate(latitude: 31.9038, longitude: 35.2034),
    radiusKm: 0.2,
  );

  test('home radius is exposed in metres', () {
    expect(home.radiusMeters, 200);
  });

  test('a fix inside the radius is at home', () {
    // ~74 m north of the home centre.
    final result = calculator.classify(
      home: home,
      fix: const Coordinate(latitude: 31.9045, longitude: 35.2034),
    )!;
    expect(result.presence, HomePresence.atHome);
    expect(result.distanceMeters, lessThan(200));
    expect(result.radiusMeters, 200);
  });

  test('a fix outside the radius is away from home', () {
    final result = calculator.classify(
      home: home,
      fix: const Coordinate(latitude: 31.9096, longitude: 35.2034),
    )!;
    expect(result.presence, HomePresence.awayFromHome);
    expect(result.distanceMeters, greaterThan(200));
  });

  test('the radius boundary is inclusive', () {
    const fix = Coordinate(latitude: 31.9056, longitude: 35.2034);
    final distance = const GeoDistance().metersBetween(home.coordinate, fix)!;
    // A home whose radius is that distance classifies as at home.
    final boundaryHome = HomeLocation(
      coordinate: home.coordinate,
      radiusKm: (distance + 0.001) / 1000,
    );
    final result = calculator.classify(home: boundaryHome, fix: fix)!;
    expect(result.distanceMeters, closeTo(distance, 0.01));
    expect(result.radiusMeters, closeTo(distance, 1));
    expect(result.presence, HomePresence.atHome);
  });

  test('accuracy is carried through next to the distance', () {
    final result = calculator.classify(
      home: home,
      fix: const Coordinate(latitude: 31.9045, longitude: 35.2034),
      accuracyMeters: 25,
    )!;
    expect(result.accuracyMeters, 25);
    expect(result.distanceMeters, isNotNull);
  });

  test('a missing accuracy stays missing rather than defaulting', () {
    final result = calculator.classify(
      home: home,
      fix: const Coordinate(latitude: 31.9045, longitude: 35.2034),
    )!;
    expect(result.accuracyMeters, isNull);
  });

  test('invalid coordinates produce no classification', () {
    expect(
      calculator.classify(
        home: home,
        fix: const Coordinate(latitude: 200, longitude: 35),
      ),
      isNull,
    );
    expect(
      calculator.classify(
        home: const HomeLocation(
          coordinate: Coordinate(latitude: -200, longitude: 0),
        ),
        fix: const Coordinate(latitude: 31, longitude: 35),
      ),
      isNull,
    );
  });

  test('home radius is configurable per home', () {
    const wide = HomeLocation(
      coordinate: Coordinate(latitude: 31.9038, longitude: 35.2034),
      radiusKm: 1,
    );
    final fix = const Coordinate(latitude: 31.9096, longitude: 35.2034);
    expect(calculator.classify(home: home, fix: fix)!.presence,
        HomePresence.awayFromHome);
    expect(calculator.classify(home: wide, fix: fix)!.presence,
        HomePresence.atHome);
  });

  test('home location can be copied with an enabled flag', () {
    final disabled = home.copyWith(enabled: false);
    expect(disabled.enabled, isFalse);
    expect(disabled.coordinate, home.coordinate);
    expect(disabled.radiusMeters, 200);
  });
}
