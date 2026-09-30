import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/app_failure.dart';
import '../firebase/firebase_error_mapper.dart';
import '../result/result.dart';
import 'data_presentation_state.dart';

/// Maps asynchronous provider state onto the application's single presentation
/// vocabulary (SRS Task 13).
///
/// Important Riverpod 3 detail: an `AsyncValue` can be *loading and failed at the
/// same time* (the loading flag is independent of the error). Using
/// `AsyncValue.when` therefore shows the loading state and hides an error that
/// has already arrived. These helpers check `hasValue` and `hasError`
/// explicitly, in priority order, so a real failure is never masked by a spinner.
abstract final class PresentationMapping {
  /// Maps `AsyncValue<T>` where a value means "loaded".
  static DataPresentation fromAsync<T>(AsyncValue<T> value) {
    if (value.hasValue) return const DataPresentation.loaded();
    return _fromErrorOrLoading(value);
  }

  /// Maps `AsyncValue<Result<T>>`, preserving the classified [AppFailure].
  ///
  /// This is the shape repositories return, so a successful-but-unavailable read
  /// is distinguishable from a failed read (SRS NFR-007, NFR-014).
  static DataPresentation fromAsyncResult<T>(AsyncValue<Result<T>> value) {
    if (value.hasValue) {
      return value.requireValue.fold(
        onSuccess: (_) => const DataPresentation.loaded(),
        onFailure: (failure) => DataPresentation.failure(failure.message),
      );
    }
    return _fromErrorOrLoading(value);
  }

  /// Maps `AsyncValue<Result<T?>>`, treating a successful `null` as [empty].
  ///
  /// Needed because "the read succeeded and there genuinely is nothing" must not
  /// be rendered as content, and must not be filled in with invented defaults
  /// (FR-048). The user profile uses this shape: a missing profile document is
  /// an empty success, never a fabricated `AppUser`.
  static DataPresentation fromAsyncNullableResult<T>(
    AsyncValue<Result<T?>> value,
  ) {
    if (value.hasValue) {
      return value.requireValue.fold(
        onSuccess: (data) => data == null
            ? const DataPresentation.empty()
            : const DataPresentation.loaded(),
        onFailure: (failure) => DataPresentation.failure(failure.message),
      );
    }
    return _fromErrorOrLoading(value);
  }

  static DataPresentation _fromErrorOrLoading(AsyncValue<Object?> value) {
    if (value.hasError) {
      final failure = FirebaseErrorMapper.toFailure(
        value.error!,
        value.stackTrace,
      );
      return DataPresentation.failure(failure.message);
    }
    return const DataPresentation.loading();
  }
}
