/// Base class for failures the application can classify and report.
///
/// Following SRS NFR-014 and NFR-045, failures are surfaced explicitly rather
/// than silently swallowed; a caught failure must never be converted into a
/// fabricated device state.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  /// Human-readable description safe to log (must not contain private data).
  final String message;

  /// Underlying error, when one exists.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// A configuration or environment problem.
class ConfigurationException extends AppException {
  const ConfigurationException(super.message, {super.cause, super.stackTrace});
}

/// A failure while talking to a backend service.
class RemoteServiceException extends AppException {
  const RemoteServiceException(super.message, {super.cause, super.stackTrace});
}

/// A failure caused by missing or revoked authorization.
class PermissionException extends AppException {
  const PermissionException(super.message, {super.cause, super.stackTrace});
}

/// A capability the current platform cannot provide (FR-068).
class UnsupportedCapabilityException extends AppException {
  const UnsupportedCapabilityException(super.message);
}
