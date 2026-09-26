import 'package:kam/core/error/app_failure.dart';
import 'package:kam/core/result/result.dart';
import 'package:kam/features/auth/domain/models/app_user.dart';
import 'package:kam/features/auth/domain/repositories/auth_repository.dart';

/// Test double for [AuthRepository].
///
/// Lets tests choose the signed-in state (including the failure path) without
/// touching Firebase. Used to prove the dependency-inversion boundary works
/// (SRS NFR-018).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user, this.failure});

  /// The user to report, or null for signed out.
  final AppUser? user;

  /// When set, every call fails with this failure.
  final AppFailure? failure;

  /// Records how many times [signOut] was called.
  int signOutCallCount = 0;

  @override
  Stream<AppUser?> watchCurrentUser() {
    final failure = this.failure;
    if (failure != null) return Stream<AppUser?>.error(failure);
    return Stream<AppUser?>.value(user);
  }

  @override
  Future<Result<AppUser?>> currentUser() async {
    final failure = this.failure;
    if (failure != null) return Failure<AppUser?>(failure);
    return Success<AppUser?>(user);
  }

  @override
  Future<Result<void>> signOut() async {
    signOutCallCount++;
    final failure = this.failure;
    if (failure != null) return Failure<void>(failure);
    return const Success<void>(null);
  }
}
