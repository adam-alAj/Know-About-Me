import 'package:flutter_test/flutter_test.dart';

import 'package:kam/app/bootstrap.dart';
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

  test('bootstrap continues without Firebase in Phase 2', () async {
    final logger = RecordingLogger();

    await AppBootstrap.initialize(logger: logger);

    expect(FirebaseBootstrap.isInitialized, isFalse);
    expect(
      logger.entries.any(
        (e) => e.level == LogLevel.info && e.message.contains('offline'),
      ),
      isTrue,
    );
  });
}
