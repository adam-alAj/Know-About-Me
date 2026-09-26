import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/unauthenticated_auth_repository.dart';
import '../../domain/models/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// The application's [AuthRepository].
///
/// This is the dependency-injection seam for identity. Tests override it with a
/// fake; Phase 3 overrides it with the Firebase implementation. See
/// `docs/decisions/ADR-005-dependency-injection-and-result.md`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => const UnauthenticatedAuthRepository(),
);

/// The signed-in user, or `null`.
///
/// Phase 2 always resolves to `null`; the shell and profile screen already
/// render that state correctly, so adding real auth later is not a UI redesign.
final currentUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchCurrentUser(),
);
