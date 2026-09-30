import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/logging/app_logger.dart';

import '../fakes/recording_logger.dart';

void main() {
  group('DeveloperAppLogger.sanitizeContext', () {
    test('redacts sensitive keys regardless of case', () {
      final sanitized = DeveloperAppLogger.sanitizeContext({
        'Token': 'abc123',
        'email': 'someone@example.com',
        'latitude': 24.7,
        'pairId': 'pair-identifier',
        'deviceId': 'device-identifier',
        'document_path': 'pairs/private-path',
        'record': {'latitude': 12.3, 'label': 'home'},
        'environment': 'development',
      });

      expect(sanitized!['Token'], '***');
      expect(sanitized['email'], '***');
      expect(sanitized['latitude'], '***');
      expect(sanitized['pairId'], '***');
      expect(sanitized['deviceId'], '***');
      expect(sanitized['document_path'], '***');
      expect(sanitized['record'], '[omitted]');
      // Non-sensitive context is preserved for diagnostics.
      expect(sanitized['environment'], 'development');
    });

    test('returns null for null context', () {
      expect(DeveloperAppLogger.sanitizeContext(null), isNull);
    });
  });

  group('RecordingLogger', () {
    test('captures entries with level and sanitized context', () {
      final logger = RecordingLogger();

      logger.info('Started', context: {'apiKey': 'secret-value'});

      expect(logger.entries, hasLength(1));
      expect(logger.entries.single.level, LogLevel.info);
      expect(logger.entries.single.context!['apiKey'], '***');
    });

    test('filters by level', () {
      final logger = RecordingLogger()
        ..debug('d')
        ..warning('w')
        ..error('e');

      expect(logger.atLeast(LogLevel.warning), hasLength(2));
    });
  });

  test('NoopAppLogger discards without throwing', () {
    const logger = NoopAppLogger();
    logger.error('ignored', error: StateError('x'));
  });
}
