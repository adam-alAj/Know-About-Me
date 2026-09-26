import 'dart:developer' as developer;

/// Severity of a log entry.
enum LogLevel {
  debug(400),
  info(800),
  warning(900),
  error(1000);

  const LogLevel(this.severity);

  /// Numeric severity compatible with `dart:developer`.
  final int severity;
}

/// Minimal logging contract so the implementation can be swapped per
/// environment without touching call sites (SRS NFR-045).
///
/// Callers must never pass passwords, authentication tokens, API secrets, or
/// precise location/identity data. Context keys named in
/// [AppLogger.sensitiveKeys] are redacted by the built-in implementation as
/// defence in depth.
abstract interface class AppLogger {
  /// Keys whose values are replaced with `***` before logging.
  static const Set<String> sensitiveKeys = {
    'password',
    'token',
    'idtoken',
    'accesstoken',
    'refreshtoken',
    'authorization',
    'apikey',
    'secret',
    'email',
    'latitude',
    'longitude',
    'location',
  };

  /// Emits one log entry.
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  });
}

/// Convenience level methods.
extension AppLoggerConvenience on AppLogger {
  void debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => log(
    LogLevel.debug,
    message,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );

  void info(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => log(
    LogLevel.info,
    message,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );

  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => log(
    LogLevel.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => log(
    LogLevel.error,
    message,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );
}

/// Default logger, backed by `dart:developer`.
///
/// Chosen over `print` because output is structured and visible in DevTools,
/// and because it can be silenced by raising [minimumLevel] in production.
class DeveloperAppLogger implements AppLogger {
  const DeveloperAppLogger({
    this.name = 'kam',
    this.minimumLevel = LogLevel.debug,
  });

  /// Logger name shown in DevTools.
  final String name;

  /// Entries below this level are dropped.
  final LogLevel minimumLevel;

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    if (level.severity < minimumLevel.severity) return;

    final safeContext = sanitizeContext(context);
    final buffer = StringBuffer(message);
    if (safeContext != null && safeContext.isNotEmpty) {
      buffer.write(' ');
      buffer.write(safeContext);
    }

    developer.log(
      buffer.toString(),
      name: name,
      level: level.severity,
      error: error,
      stackTrace: stackTrace,
      time: DateTime.now().toUtc(),
    );
  }

  /// Replaces values of sensitive keys with `***`.
  ///
  /// Exposed for testing and reuse by other logger implementations.
  static Map<String, Object?>? sanitizeContext(Map<String, Object?>? context) {
    if (context == null) return null;
    return {
      for (final entry in context.entries)
        entry.key: AppLogger.sensitiveKeys.contains(entry.key.toLowerCase())
            ? '***'
            : entry.value,
    };
  }
}

/// Discards everything. Used in tests and in builds where logging is disabled.
class NoopAppLogger implements AppLogger {
  const NoopAppLogger();

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {}
}
