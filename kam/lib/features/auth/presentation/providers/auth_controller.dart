import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../domain/models/auth_identity.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/services/auth_service.dart';
import 'auth_providers.dart';

/// Owns [AuthState]: the application's single source of truth for "who is signed
/// in" (SRS Task 2, Task 8, Task 9).
///
/// ## The provider is the source of truth
///
/// The controller subscribes to `AuthRepository.watchIdentity()` and mirrors it.
/// That stream reflects reality on every device and across app restarts, so
/// session restoration needs no special startup code: the first event *is* the
/// restoration (SRS Task 8, Task 24).
///
/// ## Why operations also set state
///
/// `signIn`/`register`/`signOut` additionally apply their own outcome, so the UI
/// never has to wait for stream timing to leave a spinner. Both paths agree on
/// the same identity; the stream remains authoritative if they ever disagree.
///
/// ## No half-states
///
/// A failed operation restores the previous state, so the app is never left
/// "authenticating" with no request in flight, and a failed sign-out leaves the
/// user signed in rather than showing an empty authenticated shell.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<AuthIdentity?>? _subscription;

  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);

    // Auth state changes are pushed, not polled: this is also what makes an
    // expired or externally revoked session surface without user action.
    _subscription = repository.watchIdentity().listen(
      _onIdentity,
      onError: _onStreamError,
    );
    ref.onDispose(() => _subscription?.cancel());

    return const AuthInitializing();
  }

  /// Re-runs initialization, for example after the account service recovered.
  ///
  /// Used by the splash screen's retry action; makes an [AuthError] recoverable
  /// without restarting the app (SRS Task 21).
  void retry() => ref.invalidateSelf();

  /// Signs in with email and password (SRS Task 6).
  Future<Result<AuthIdentity>> signIn({
    required String email,
    required String password,
  }) async {
    if (state.isBusy) {
      return const Failure<AuthIdentity>(
        AuthenticationFailure(
          'An authentication request is already in progress.',
        ),
      );
    }

    final previous = state.identity;
    state = AuthAuthenticating(previous: previous);

    final result = await _service.signIn(email: email, password: password);

    switch (result) {
      case Success<AuthIdentity>(:final value):
        state = AuthAuthenticated(value);
      case Failure<AuthIdentity>(:final failure):
        // Nothing changed at the provider, so restore the pre-attempt state and
        // let the screen show the reason.
        _restoreAfterFailure(previous);
        _logFailure('signIn', failure);
    }
    return result;
  }

  /// Registers an account and its profile (SRS Task 4, Task 5).
  ///
  /// See `RegistrationResult` for the partial-failure contract: an account whose
  /// profile could not be stored stays signed in and is reported as
  /// [RegistrationProfilePending], never as a success.
  Future<RegistrationResult> register({
    required String email,
    required String password,
    required String confirmPassword,
    required String displayName,
  }) async {
    if (state.isBusy) {
      return const RegistrationRejected(
        AuthenticationFailure(
          'An authentication request is already in progress.',
        ),
      );
    }

    final previous = state.identity;
    state = AuthAuthenticating(previous: previous);

    final result = await _service.register(
      email: email,
      password: password,
      confirmPassword: confirmPassword,
      displayName: displayName,
    );

    switch (result) {
      case RegistrationComplete(:final identity):
      case RegistrationProfilePending(:final identity):
        // The account exists, so reflect it immediately instead of waiting for
        // the identity stream. A pending profile is surfaced by the profile
        // screen and the dashboard as an explicit "not set up yet" state.
        state = AuthAuthenticated(identity);
      case RegistrationRejected(:final failure):
        _restoreAfterFailure(previous);
        _logFailure('register', failure);
    }
    return result;
  }

  /// Ends the session (SRS Task 7).
  ///
  /// Clears the local authenticated state, signs out of the provider, and drops
  /// cached profile/preferences state so no authenticated data survives the
  /// sign-out. The account and its documents are untouched.
  Future<Result<void>> signOut() async {
    final identity = state.identity;
    if (identity == null) return const Success<void>(null);

    state = AuthSigningOut(identity);
    final result = await _service.signOut();

    switch (result) {
      case Success<void>():
        state = const AuthUnauthenticated();
        // Keyed providers keep one entry per uid; invalidating the families
        // releases the signed-out user's profile and settings from memory.
        ref.invalidate(userProfileProvider);
        ref.invalidate(userPreferencesProvider);
      case Failure<void>(:final failure):
        // The provider still considers us signed in, so do not pretend otherwise.
        state = AuthAuthenticated(identity);
        _logFailure('signOut', failure);
    }
    return result;
  }

  AuthService get _service => ref.read(authServiceProvider);

  void _onIdentity(AuthIdentity? identity) {
    state = identity == null
        ? const AuthUnauthenticated()
        : AuthAuthenticated(identity);
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    // "Unknown" is not "signed out": presenting a sign-in form here would hide a
    // real outage and could silently discard a live session (SRS Task 21).
    final failure = AppFailure.fromException(error, stackTrace);
    ref
        .read(loggerProvider)
        .error(
          'Authentication state is unavailable',
          error: error,
          stackTrace: stackTrace,
          context: {'failureType': failure.type.name},
        );
    state = AuthError(failure);
  }

  void _restoreAfterFailure(AuthIdentity? previous) {
    state = previous == null
        ? const AuthUnauthenticated()
        : AuthAuthenticated(previous);
  }

  void _logFailure(String operation, AppFailure failure) {
    // Operation names and failure categories only: credentials, tokens and email
    // addresses must never reach a log (constraint 7, NFR-045).
    ref
        .read(loggerProvider)
        .warning(
          'Authentication operation failed',
          context: {'operation': operation, 'failureType': failure.type.name},
        );
  }
}
