import 'package:flutter/material.dart';

import '../../connectivity/connection_status.dart';
import '../../constants/app_spacing.dart';

/// A compact, calm statement of the connection state (Phase 20 §25, §26).
///
/// It reports **only** states the application can evidence, and never invents a
/// reason for one:
///
/// * no error codes, no document paths, no rule details — nothing technical
///   reaches the user;
/// * the words are about *this connection*, never about the other person, so
///   "offline" can never read as "their phone is off" (Phase 20 §9);
/// * it says nothing at all when nothing is wrong, because a persistent "all
///   good" badge is noise rather than reassurance.
///
/// Text plus icon, and colour only as secondary reinforcement, so the meaning
/// survives greyscale (NFR-028).
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({
    super.key,
    required this.status,
    this.showWhenConnected = false,
  });

  /// The connection as this device can evidence it.
  final ConnectionStatus status;

  /// Whether to speak while everything is nominal. Off by default so the
  /// indicator stays out of the way during normal use.
  final bool showWhenConnected;

  /// Shown while the backend is reachable and nothing is queued.
  static const String connectedLabel = 'Connected';

  /// Shown while the last evidence says the backend is unreachable.
  static const String offlineLabel = 'Offline';

  /// Shown when a write failed for a reason that may fix itself.
  static const String retryingLabel = 'Retrying';

  /// Shown while a reconnection is still being caught up on.
  static const String catchingUpLabel = 'Catching up…';

  /// Shown while a write is in flight.
  static const String syncingLabel = 'Syncing…';

  /// Shown while a local change is waiting for the backend to acknowledge it.
  static const String waitingLabel = 'Waiting to sync';

  /// Shown when the backend refused the work permanently.
  static const String blockedLabel = 'Permission required';

  /// The label for [status], or `null` when there is nothing honest to say.
  ///
  /// Ordered by what the user most needs to know, not by how the status is
  /// modelled: an unreachable backend matters more than the fact that a write
  /// is queued behind it.
  static String? labelFor(ConnectionStatus status) {
    if (status.isUnknown) return null;
    if (status.isBlocked) return blockedLabel;
    if (status.isOffline) return offlineLabel;
    if (status.recovery == RecoveryState.inProgress) return catchingUpLabel;
    if (status.isRetrying) return retryingLabel;
    if (status.synchronization == SynchronizationState.syncing) {
      return syncingLabel;
    }
    if (status.synchronization == SynchronizationState.pending) {
      return waitingLabel;
    }
    return connectedLabel;
  }

  static IconData _iconFor(ConnectionStatus status) {
    if (status.isBlocked) return Icons.lock_outline;
    if (status.isOffline) return Icons.cloud_off_outlined;
    if (status.isRetrying || status.recovery == RecoveryState.inProgress) {
      return Icons.sync_problem_outlined;
    }
    if (status.hasUnsyncedChanges) return Icons.sync_outlined;
    return Icons.cloud_done_outlined;
  }

  /// Whether anything should be rendered for [status].
  bool get isVisible {
    final label = labelFor(status);
    if (label == null) return false;
    if (status.isNominal && !showWhenConnected) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final label = labelFor(status);
    if (label == null || (status.isNominal && !showWhenConnected)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needsAttention =
        status.isBlocked || status.isOffline || status.isRetrying;
    final (foreground, background) = needsAttention
        ? (scheme.onErrorContainer, scheme.errorContainer)
        : (scheme.onSurfaceVariant, scheme.surfaceContainerHighest);

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(status), size: 16, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
