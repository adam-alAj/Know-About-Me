import '../../../../core/result/result.dart';
import '../../domain/models/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Placeholder [AuthRepository] used until Firebase Authentication is wired up.
///
/// There is never a signed-in user, and it never invents one. This keeps the
/// application honest while still exercising the real dependency boundary:
/// routing, the shell and the profile screen are built against the interface,
/// not against a stub.
class UnauthenticatedAuthRepository implements AuthRepository {
  const UnauthenticatedAuthRepository();

  @override
  Stream<AppUser?> watchCurrentUser() => Stream<AppUser?>.value(null);

  @override
  Future<Result<AppUser?>> currentUser() async => const Success<AppUser?>(null);

  @override
  Future<Result<void>> signOut() async {
    // Nothing to sign out of yet; Phase 3 implements this against Firebase Auth.
    return const Success<void>(null);
  }
}
