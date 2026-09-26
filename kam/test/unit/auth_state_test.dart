import 'package:flutter_test/flutter_test.dart';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/domain/models/auth_state.dart';

void main() {
  const identity = AuthIdentity(uid: 'user-a', email: 'afraa@example.com');

  test('AuthInitializing is neither authenticated nor busy', () {
    const state = AuthInitializing();

    expect(state.identity, isNull);
    expect(state.isAuthenticated, isFalse);
    expect(state.isBusy, isFalse);
    expect(state.isUnavailable, isFalse);
  });

  test('AuthUnauthenticated has no identity', () {
    const state = AuthUnauthenticated();

    expect(state.identity, isNull);
    expect(state.isAuthenticated, isFalse);
  });

  test('AuthAuthenticated exposes its identity', () {
    const state = AuthAuthenticated(identity);

    expect(state.identity, identity);
    expect(state.isAuthenticated, isTrue);
    expect(state.isBusy, isFalse);
  });

  test('AuthAuthenticating reports busy and keeps any previous identity', () {
    expect(const AuthAuthenticating().isBusy, isTrue);
    expect(const AuthAuthenticating().identity, isNull);

    const reauth = AuthAuthenticating(previous: identity);
    expect(reauth.isBusy, isTrue);
    // Keeping the previous identity is what stops a re-authentication from
    // blanking the signed-in UI.
    expect(reauth.identity, identity);
  });

  test('AuthSigningOut still counts as authenticated and busy', () {
    const state = AuthSigningOut(identity);

    expect(state.isAuthenticated, isTrue);
    expect(state.isBusy, isTrue);
  });

  test('AuthError is unavailable and never authenticated', () {
    const state = AuthError(RemoteServiceFailure('Account service is down'));

    expect(state.isUnavailable, isTrue);
    expect(state.isAuthenticated, isFalse);
    expect(state.isBusy, isFalse);
  });

  test('AuthIdentity never prints the email', () {
    // Logs and error reports must not carry personal data (NFR-045).
    expect(identity.toString(), isNot(contains('afraa@example.com')));
    expect(identity.toString(), contains('user-a'));
  });

  test('AuthIdentity compares by value', () {
    expect(
      const AuthIdentity(uid: 'a', email: 'e@x.com'),
      const AuthIdentity(uid: 'a', email: 'e@x.com'),
    );
    expect(const AuthIdentity(uid: 'a'), isNot(const AuthIdentity(uid: 'b')));
  });
}
