import '../../../../core/result/result.dart';
import '../models/app_user.dart';

/// Contract for identity and profile access.
///
/// Firebase Authentication will implement this in Phase 3. The presentation
/// layer never talks to Firebase directly (SRS constraint 2 in Phase 2 brief,
/// NFR-017), so this interface is the only thing routing and UI depend on.
///
/// Implementations must return `Result`/`Failure` rather than throwing, and must
/// return `null` when nobody is signed in rather than fabricating a user.
abstract interface class AuthRepository {
  /// Emits the signed-in user, or `null` when signed out.
  Stream<AppUser?> watchCurrentUser();

  /// Reads the signed-in user once.
  Future<Result<AppUser?>> currentUser();

  /// Signs the current user out.
  Future<Result<void>> signOut();
}
