import '../../../../core/error/app_failure.dart';
import 'auth_identity.dart';

/// The application's authentication state (SRS Task 2 of the Phase 4 brief).
///
/// This is **application** state, not ephemeral form state: the router and the
/// profile feature must observe it, so it lives in a provider rather than in a
/// widget (ADR-006).
///
/// `sealed` so every consumer (router guard, screens) must handle all cases; a
/// new state becomes a compile error until it is handled.
sealed class AuthState {
  const AuthState();

  /// The identity known so far, if any.
  ///
  /// Non-null while authenticating or signing out, so the UI can keep showing the
  /// affected account instead of flashing an empty shell.
  AuthIdentity? get identity => switch (this) {
    AuthAuthenticated(:final identity) => identity,
    AuthSigningOut(:final identity) => identity,
    _ => null,
  };

  /// Whether an identity is currently established (including mid-sign-out).
  ///
  /// The guard treats signing-out as authenticated on purpose: redirecting away
  /// mid-sign-out would produce a visible bounce (SRS Task 10: no flickering).
  bool get isAuthenticated => identity != null;

  /// Whether an authentication operation is in flight.
  bool get isBusy => this is AuthAuthenticating || this is AuthSigningOut;

  /// Whether the authentication state itself could not be determined.
  bool get isUnavailable => this is AuthError;
}

/// Identity has not been determined yet; the app must not show protected content.
final class AuthInitializing extends AuthState {
  const AuthInitializing();

  @override
  String toString() => 'AuthInitializing()';
}

/// Nobody is signed in. The user may register or sign in.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();

  @override
  String toString() => 'AuthUnauthenticated()';
}

/// A sign-in or registration request is in flight.
///
/// Holds the identity of a previously signed-in user when one exists, so a
/// re-authentication does not blank the UI.
final class AuthAuthenticating extends AuthState {
  const AuthAuthenticating({this.previous});

  /// The identity that was current before this attempt, if any.
  final AuthIdentity? previous;

  @override
  AuthIdentity? get identity => previous;

  @override
  String toString() => 'AuthAuthenticating()';
}

/// An identity is established.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.identity);

  @override
  final AuthIdentity identity;

  @override
  String toString() => 'AuthAuthenticated(${identity.uid})';
}

/// A sign-out request is in flight.
///
/// Retains [identity] while the request is outstanding so the UI does not show
/// unauthenticated content before the provider confirms it.
final class AuthSigningOut extends AuthState {
  const AuthSigningOut(this.identity);

  @override
  final AuthIdentity identity;

  @override
  String toString() => 'AuthSigningOut(${identity.uid})';
}

/// The authentication state could not be determined.
///
/// Reached when the provider is unreachable or this build has no account service
/// configured. The app must show this explicitly rather than an empty sign-in
/// form that cannot work, and must never fall back to the authenticated area
/// (SRS Task 21, constraint 10: no fabricated availability).
final class AuthError extends AuthState {
  const AuthError(this.failure);

  /// Classified, user-safe reason (NFR-045).
  final AppFailure failure;

  @override
  String toString() => 'AuthError(${failure.type.name})';
}
