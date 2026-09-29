import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/ui/widgets/connection_indicator.dart';
import '../providers/connection_providers.dart';

/// The application-wide connection strip (Phase 20 §26).
///
/// Mounted once, in the shell, so the state is stated in one place rather than
/// re-derived per screen. It renders **nothing** whenever the connection is
/// nominal or unknown, so it never competes with the content the user came for:
///
/// ```text
/// connected + idle   → nothing      (there is nothing to say)
/// no evidence yet    → nothing      ("unknown" is not "offline")
/// offline / syncing  → one quiet line
/// ```
class ConnectionStatusBanner extends ConsumerWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    if (status.isNominal) return const SizedBox.shrink();
    if (ConnectionIndicator.labelFor(status) == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConnectionIndicator(status: status),
      ),
    );
  }
}
