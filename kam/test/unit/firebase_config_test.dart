import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/config/app_config.dart';
import 'package:kam/core/config/app_environment.dart';
import 'package:kam/core/firebase/firebase_config.dart';

void main() {
  const complete = AppConfig(
    environment: AppEnvironment.development,
    enableVerboseLogging: true,
    firebaseProjectId: 'demo-kam',
    firebaseApiKey: 'client-safe-api-key',
    firebaseAppId: '1:1:android:abc',
    firebaseMessagingSenderId: '1',
  );

  const empty = AppConfig(
    environment: AppEnvironment.development,
    enableVerboseLogging: true,
  );

  const partial = AppConfig(
    environment: AppEnvironment.development,
    enableVerboseLogging: true,
    firebaseProjectId: 'demo-kam',
  );

  group('AppConfig Firebase flags', () {
    test('a complete set of identifiers counts as configured', () {
      expect(complete.hasFirebaseConfiguration, isTrue);
      expect(complete.hasPartialFirebaseConfiguration, isFalse);
    });

    test('no identifiers means not configured', () {
      expect(empty.hasFirebaseConfiguration, isFalse);
      expect(empty.hasPartialFirebaseConfiguration, isFalse);
    });

    test(
      'a partial set is reported as a misconfiguration, not as configured',
      () {
        expect(partial.hasFirebaseConfiguration, isFalse);
        expect(partial.hasPartialFirebaseConfiguration, isTrue);
      },
    );

    test('requesting emulators without a project is flagged', () {
      const misconfigured = AppConfig(
        environment: AppEnvironment.development,
        enableVerboseLogging: true,
        useFirebaseEmulators: true,
      );

      expect(misconfigured.hasMisconfiguredEmulatorRequest, isTrue);
      expect(complete.hasMisconfiguredEmulatorRequest, isFalse);
    });

    test('toString never exposes anything beyond the project id', () {
      expect(complete.toString(), contains('demo-kam'));
      expect(complete.toString(), isNot(contains('client-safe-api-key')));
      expect(complete.toString(), isNot(contains('1:1:android:abc')));
    });
  });

  group('FirebaseConfig', () {
    test('isConfigured mirrors AppConfig', () {
      expect(FirebaseConfig.isConfigured(complete), isTrue);
      expect(FirebaseConfig.isConfigured(empty), isFalse);
      expect(FirebaseConfig.isConfigured(partial), isFalse);
    });

    test('optionsFor builds FirebaseOptions from client-safe values', () {
      final options = FirebaseConfig.optionsFor(complete);

      expect(options.projectId, 'demo-kam');
      expect(options.appId, '1:1:android:abc');
      expect(options.messagingSenderId, '1');
      expect(options.apiKey, 'client-safe-api-key');
    });

    test('optionsFor refuses to build a half-configured project', () {
      expect(() => FirebaseConfig.optionsFor(partial), throwsStateError);
      expect(() => FirebaseConfig.optionsFor(empty), throwsStateError);
    });
  });
}
