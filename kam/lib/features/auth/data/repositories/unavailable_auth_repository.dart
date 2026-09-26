import '../../../../core/error/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/models/auth_identity.dart';
import '../../domain/repositories/auth_repository.dart';

/// [AuthRepository] used when this build has no reachable account service.
///
/// Chosen by `authRepositoryProvider` when Firebase was not configured or failed
/// to initialize. It is not a stub that pretends to work: every credential
/// operation fails with a [ConfigurationFailure] explaining the real situation,
/// while "nobody is signed in" is reported truthfully as `null`.
///
/// This is what keeps the app honest in a build without a Firebase project: the
/// sign-in screen states that accounts are unavailable instead of offering a form
/// that cannot succeed (SRS constraint 10).
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository({
    this.reason =
        'Accounts are unavailable in this build because no account service is '
        'configured.',
  });

  /// User-safe explanation, shown by the sign-in screen.
  final String reason;

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason => reason;

  @override
  Stream<AuthIdentity?> watchIdentity() => Stream<AuthIdentity?>.value(null);

  @override
  Future<Result<AuthIdentity?>> currentIdentity() async =>
      const Success<AuthIdentity?>(null);

  @override
  Future<Result<AuthIdentity>> registerWithEmail({
    required String email,
    required String password,
  }) async => Failure<AuthIdentity>(ConfigurationFailure(reason));

  @override
  Future<Result<AuthIdentity>> signInWithEmail({
    required String email,
    required String password,
  }) async => Failure<AuthIdentity>(ConfigurationFailure(reason));

  @override
  Future<Result<void>> signOut() async => const Success<void>(null);
}
