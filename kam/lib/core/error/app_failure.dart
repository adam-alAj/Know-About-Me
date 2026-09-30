import 'app_exception.dart';

/// Broad category of a failure, used by the UI to choose how to present it.
///
/// Follows SRS NFR-014, NFR-015 and NFR-045: failures are classified and
/// surfaced instead of being swallowed, and are never converted into a
/// fabricated device state.
enum FailureType {
  /// Nothing more specific is known.
  unexpected,

  /// Invalid or missing application configuration.
  configuration,

  /// A backend or plugin call failed.
  remoteService,

  /// A permission is missing or was revoked (FR-067).
  permission,

  /// The user is not authenticated or not authorized.
  authentication,

  /// The server rejected access under the current authorization state.
  authorization,

  /// A local persistence operation could not be completed.
  localStorage,

  /// The platform cannot provide the requested capability (FR-068).
  unsupportedCapability,

  /// Input failed validation.
  validation,

  /// The requested resource does not exist.
  notFound,
}

/// A classified, user-presentable failure.
///
/// This is the error type carried by `Result`. It is intentionally distinct
/// from [AppException]:
///
/// - [AppException] is what low-level code *throws* (often wrapping a plugin or
///   SDK exception).
/// - [AppFailure] is what application code *returns* in a `Result`, once the
///   exception has been classified and made safe to display.
///
/// Nothing here exposes backend internals or secrets; [message] is written to be
/// safe for a user to read (SRS NFR-045, constraint: do not leak internals).
sealed class AppFailure {
  const AppFailure(
    this.message, {
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Classifies an arbitrary error into an [AppFailure].
  ///
  /// Used by `Result.guard` and by repositories when an external call throws.
  static AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;

    if (error is ConfigurationException) {
      return ConfigurationFailure(
        error.message,
        cause: error.cause,
        stackTrace: error.stackTrace ?? stackTrace,
      );
    }
    if (error is RemoteServiceException) {
      return RemoteServiceFailure(
        error.message,
        cause: error.cause,
        stackTrace: error.stackTrace ?? stackTrace,
      );
    }
    if (error is PermissionException) {
      return PermissionFailure(
        error.message,
        cause: error.cause,
        stackTrace: error.stackTrace ?? stackTrace,
      );
    }
    if (error is UnsupportedCapabilityException) {
      return UnsupportedCapabilityFailure(
        error.message,
        stackTrace: stackTrace,
      );
    }

    return UnexpectedFailure(
      'Something went wrong. Please try again.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Classification of this failure.
  final FailureType type;

  /// Message safe to show to a user.
  final String message;

  /// The underlying error, retained for logging only.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType(${type.name}): $message';
}

/// A failure that could not be classified further.
class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.unexpected);
}

/// Invalid or missing configuration.
class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.configuration);
}

/// A backend, SDK or plugin call failed.
class RemoteServiceFailure extends AppFailure {
  const RemoteServiceFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.remoteService);
}

/// Missing or revoked permission (FR-067).
class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.permission);
}

/// The user is not authenticated or not authorized (FR-062).
class AuthenticationFailure extends AppFailure {
  const AuthenticationFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.authentication);
}

/// The current server-side authorization no longer permits the action.
///
/// Kept distinct from [PermissionFailure], which represents an OS/runtime
/// permission such as location or notifications.
class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.authorization);
}

/// A local persistence operation failed. The caller may still have remote data.
class LocalStorageFailure extends AppFailure {
  const LocalStorageFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.localStorage);
}

/// The current platform cannot provide the requested capability (FR-068).
class UnsupportedCapabilityFailure extends AppFailure {
  const UnsupportedCapabilityFailure(super.message, {super.stackTrace})
    : super(type: FailureType.unsupportedCapability);
}

/// Input failed validation.
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.validation);
}

/// The requested resource was not found.
class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.cause, super.stackTrace})
    : super(type: FailureType.notFound);
}
