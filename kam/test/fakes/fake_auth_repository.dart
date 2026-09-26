import 'dart:async';

import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/features/auth/domain/models/auth_identity.dart';
import 'package:kam/features/auth/domain/repositories/auth_repository.dart';

/// Test double for [AuthRepository] (SRS Task 23, Task 17 of the brief).
///
/// Mirrors the behaviour the real repository must have, so the tests exercise the
/// production code paths rather than a simplified fiction:
///
/// - [watchIdentity] replays the current identity on subscribe (like
///   `authStateChanges`), then pushes changes;
/// - a successful register/sign-in **emits the new identity**;
/// - sign-out emits `null`.
///
/// It never touches Firebase, so no test needs a project or a platform channel.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AuthIdentity? initialIdentity,
    this.isAvailable = true,
    this.unavailableReason,
    this.registrationFailure,
    this.signInFailure,
    this.signOutFailure,
    this.registeredUid = 'user-new',
    this.operationDelay = Duration.zero,
  }) : _current = initialIdentity;

  /// Artificial latency, so a test can observe the in-flight state.
  Duration operationDelay;

  final StreamController<AuthIdentity?> _changes =
      StreamController<AuthIdentity?>.broadcast();

  AuthIdentity? _current;

  /// Whether an account service is reported as reachable.
  @override
  bool isAvailable;

  @override
  String? unavailableReason;

  /// When set, the corresponding operation fails with it.
  AppFailure? registrationFailure;
  AppFailure? signInFailure;
  AppFailure? signOutFailure;

  /// The uid a successful registration reports.
  String registeredUid;

  int registerCallCount = 0;
  int signInCallCount = 0;
  int signOutCallCount = 0;

  /// The identity the fake currently considers signed in.
  AuthIdentity? get signedInIdentity => _current;

  @override
  Stream<AuthIdentity?> watchIdentity() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<Result<AuthIdentity?>> currentIdentity() async =>
      Success<AuthIdentity?>(_current);

  @override
  Future<Result<AuthIdentity>> registerWithEmail({
    required String email,
    required String password,
  }) async {
    registerCallCount++;
    await _delay();
    final failure = registrationFailure;
    if (failure != null) return Failure<AuthIdentity>(failure);
    return Success<AuthIdentity>(
      _publishIdentity(AuthIdentity(uid: registeredUid, email: email)),
    );
  }

  @override
  Future<Result<AuthIdentity>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signInCallCount++;
    await _delay();
    final failure = signInFailure;
    if (failure != null) return Failure<AuthIdentity>(failure);
    return Success<AuthIdentity>(
      _publishIdentity(AuthIdentity(uid: 'user-a', email: email)),
    );
  }

  @override
  Future<Result<void>> signOut() async {
    signOutCallCount++;
    await _delay();
    final failure = signOutFailure;
    if (failure != null) return Failure<void>(failure);
    _clearIdentity();
    return const Success<void>(null);
  }

  /// Simulates the session ending outside this device (expiry, revocation on
  /// another device), which the app must handle without user action.
  void simulateExternalSignOut() => _clearIdentity();

  /// Simulates the identity stream failing, which must produce `AuthError` rather
  /// than a silent sign-out.
  void simulateStreamError(AppFailure failure) {
    if (!_changes.isClosed) _changes.addError(failure);
  }

  /// Releases the stream. Call from `addTearDown`.
  void dispose() {
    if (!_changes.isClosed) _changes.close();
  }

  Future<void> _delay() => operationDelay == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(operationDelay);

  AuthIdentity _publishIdentity(AuthIdentity identity) {
    _current = identity;
    if (!_changes.isClosed) _changes.add(identity);
    return identity;
  }

  void _clearIdentity() {
    _current = null;
    if (!_changes.isClosed) _changes.add(null);
  }
}
