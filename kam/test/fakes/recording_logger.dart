import 'package:kam/core/logging/app_logger.dart';

/// One captured log entry.
class LogEntry {
  const LogEntry(this.level, this.message, this.context);

  final LogLevel level;
  final String message;
  final Map<String, Object?>? context;
}

/// [AppLogger] that records entries so tests can assert on them.
class RecordingLogger implements AppLogger {
  final List<LogEntry> entries = [];

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    entries.add(
      LogEntry(level, message, DeveloperAppLogger.sanitizeContext(context)),
    );
  }

  /// Entries at or above [level].
  List<LogEntry> atLeast(LogLevel level) =>
      entries.where((e) => e.level.severity >= level.severity).toList();
}
