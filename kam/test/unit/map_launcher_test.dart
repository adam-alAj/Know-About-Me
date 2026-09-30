import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kam/features/device_state/data/maps/method_channel_map_launcher.dart';

/// The map action must be an explicit, honest action: it either opens an
/// external map application or reports that it could not, and it never invokes
/// the platform on a target that has no map deep-link mechanism.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kam/map_launcher');

  void setHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends only the authorized coordinate and reports success', () async {
    MethodCall? received;
    setHandler((call) async {
      received = call;
      return true;
    });

    final launcher = MethodChannelMapLauncher('android');
    expect(launcher.isSupported, isTrue);

    final opened = await launcher.openCoordinates(
      latitude: 52.5,
      longitude: 13.4,
    );

    expect(opened, isTrue);
    expect(received?.method, 'openCoordinates');
    expect(received?.arguments, <String, Object?>{
      'latitude': 52.5,
      'longitude': 13.4,
    });
  });

  test('a label travels with the coordinate and never replaces it', () async {
    MethodCall? received;
    setHandler((call) async {
      received = call;
      return true;
    });

    await MethodChannelMapLauncher(
      'android',
    ).openCoordinates(latitude: 1.5, longitude: 2.5, label: ' Partner home ');

    expect(received?.arguments, <String, Object?>{
      'latitude': 1.5,
      'longitude': 2.5,
      'label': 'Partner home',
    });
  });

  test('an unsupported platform never invokes the channel', () async {
    var called = false;
    setHandler((call) async {
      called = true;
      return true;
    });

    final launcher = MethodChannelMapLauncher('windows');
    expect(launcher.isSupported, isFalse);
    expect(
      await launcher.openCoordinates(latitude: 1, longitude: 2),
      isFalse,
    );
    expect(called, isFalse);
  });

  test('a platform refusal becomes an honest failure, not a crash', () async {
    setHandler((call) async {
      throw PlatformException(code: 'no_handler');
    });

    expect(
      await MethodChannelMapLauncher(
        'android',
      ).openCoordinates(latitude: 1, longitude: 2),
      isFalse,
    );
  });
}
