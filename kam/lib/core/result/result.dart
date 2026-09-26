import '../error/app_failure.dart';

/// The outcome of an operation that can fail in an expected way.
///
/// Replaces scattered `try/catch` blocks with one explicit, exhaustively
/// switchable type (SRS NFR-014, NFR-018). Repositories return `Result`; the
/// presentation layer maps it to a `DataPresentation`/`AppFailure`.
sealed class Result<T> {
  const Result();

  /// Runs [action], converting any thrown error into a [Failure].
  ///
  /// Use this at the boundary of external code (plugins, SDKs, network); inside
  /// the application prefer returning `Result` values directly.
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } catch (error, stackTrace) {
      return Failure<T>(AppFailure.fromException(error, stackTrace));
    }
  }

  /// Synchronous counterpart of [guard].
  static Result<T> guardSync<T>(T Function() action) {
    try {
      return Success<T>(action());
    } catch (error, stackTrace) {
      return Failure<T>(AppFailure.fromException(error, stackTrace));
    }
  }

  /// Whether this is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Whether this is a [Failure].
  bool get isFailure => this is Failure<T>;

  /// The value when successful, otherwise `null`.
  ///
  /// Note: `null` is also a legitimate success value, so prefer [fold] or a
  /// `switch` when the distinction matters.
  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    Failure<T>() => null,
  };

  /// The failure when unsuccessful, otherwise `null`.
  AppFailure? get failureOrNull => switch (this) {
    Success<T>() => null,
    Failure<T>(:final failure) => failure,
  };

  /// Collapses both branches into a single value.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final value) => onSuccess(value),
      Failure<T>(:final failure) => onFailure(failure),
    };
  }

  /// Transforms a successful value while leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(:final value) => Success<R>(transform(value)),
      Failure<T>(:final failure) => Failure<R>(failure),
    };
  }

  @override
  String toString() => switch (this) {
    Success<T>(:final value) => 'Success($value)',
    Failure<T>(:final failure) => 'Failure($failure)',
  };
}

/// A successful [Result].
final class Success<T> extends Result<T> {
  const Success(this.value);

  /// The produced value.
  final T value;

  @override
  bool operator ==(Object other) => other is Success<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A failed [Result].
final class Failure<T> extends Result<T> {
  const Failure(this.failure);

  /// Why the operation failed.
  final AppFailure failure;

  @override
  bool operator ==(Object other) =>
      other is Failure<T> && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;
}
