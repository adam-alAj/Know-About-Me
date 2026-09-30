import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/logging/app_logger.dart';

/// Application-wide fallback for unexpected build errors.
///
/// Replaces Flutter's default error widget so a broken subtree shows a calm,
/// non-technical message instead of an alarming red screen (SRS Task 14).
/// Details are still shown while `kDebugMode` is true so developers keep the
/// information they need; nothing sensitive is ever rendered.
abstract final class AppErrorBoundary {
  /// Installs the boundary. Called once during bootstrap.
  static void install({required AppLogger logger}) {
    ErrorWidget.builder = (FlutterErrorDetails details) =>
        AppErrorFallbackScreen(details: details);

    FlutterError.onError = (details) {
      logger.error(
        'Unhandled Flutter framework error',
        error: details.exception,
        stackTrace: details.stack,
        context: {'errorType': details.exception.runtimeType.toString()},
      );
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      logger.error(
        'Unhandled asynchronous application error',
        error: error,
        stackTrace: stackTrace,
        context: {'errorType': error.runtimeType.toString()},
      );
      return true;
    };
  }
}

/// The screen shown when a widget fails to build.
class AppErrorFallbackScreen extends StatelessWidget {
  const AppErrorFallbackScreen({super.key, this.details});

  /// Error details, used only in debug builds.
  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.report_problem_outlined,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'This part of the app could not be displayed.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (kDebugMode && details != null) ...[
                const SizedBox(height: 12),
                Text(
                  details!.exceptionAsString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
