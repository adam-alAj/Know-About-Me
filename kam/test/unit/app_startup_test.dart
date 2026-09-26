import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/bootstrap.dart';
import 'package:kam/core/config/app_config.dart';
import 'package:kam/core/config/app_environment.dart';
import 'package:kam/core/firebase/firebase_bootstrap.dart';
import 'package:kam/core/logging/app_logger.dart';

import '../fakes/recording_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstrap resolves configuration and logs the sequence', () async {
    final logger = RecordingLogger();

    final config = await AppBootstrap.initialize(logger: logger);

    expect(config.environment, AppEnvironment.development);
    expect(logger.entries, isNotEmpty);
    expect(logger.entries.first.message, contains('Application starting'));
  });

  test(
    'bootstrap continues without Firebase when it is not configured',
    () async {
      final logger = RecordingLogger();

      await AppBootstrap.initialize(logger: logger);

      expect(FirebaseBootstrap.isInitialized, isFalse);
      expect(
        logger.entries.any(
          (e) => e.level == LogLevel.info && e.message.contains('offline'),
        ),
        isTrue,
      );
    },
  );

  group('FirebaseBootstrap', () {
    tearDown(FirebaseBootstrap.reset);

    const unconfigured = AppConfig(
      environment: AppEnvironment.development,
      enableVerboseLogging: true,
    );

    const partial = AppConfig(
      environment: AppEnvironment.development,
      enableVerboseLogging: true,
      firebaseProjectId: 'demo-kam',
    );

    test(
      'stays uninitialized and logs when Firebase is not configured',
      () async {
        final logger = RecordingLogger();

        final ready = await FirebaseBootstrap.initialize(
          unconfigured,
          logger: logger,
        );

        expect(ready, isFalse);
        expect(FirebaseBootstrap.isInitialized, isFalse);
        expect(FirebaseBootstrap.lastFailure, isNull);
        expect(logger.entries.single.message, contains('not configured'));
      },
    );

    test(
      'warns loudly (but does not throw) on a partial configuration',
      () async {
        final logger = RecordingLogger();

        final ready = await FirebaseBootstrap.initialize(
          partial,
          logger: logger,
        );

        expect(ready, isFalse);
        expect(FirebaseBootstrap.isInitialized, isFalse);
        expect(
          logger.entries.any(
            (e) =>
                e.level == LogLevel.warning && e.message.contains('incomplete'),
          ),
          isTrue,
        );
      },
    );
  });
}
