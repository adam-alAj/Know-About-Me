import 'package:flutter_test/flutter_test.dart';
import 'package:kam/core/connectivity/connection_status.dart';

/// Phase 20 §3, §23: the connection model must be able to say *exactly* what the
/// application can evidence, and nothing more.
///
/// The property these tests protect is the one the whole phase rests on:
/// `offline ≠ powered off`, `unknown ≠ offline`, and
/// `permission-denied ≠ unavailable`.
void main() {
  group('Connectivity derivation', () {
    test('no evidence at all is unknown, never offline', () {
      expect(ConnectionEvidence.none.connectivity, ConnectivityState.unknown);
    });

    test('a queued write proves the backend is unreachable', () {
      const evidence = ConnectionEvidence(
        hasAnyDocument: true,
        hasServerConfirmedDocument: true,
        hasPendingWrites: true,
      );
      expect(evidence.connectivity, ConnectivityState.offline);
    });

    test('a network failure proves the backend is unreachable', () {
      const evidence = ConnectionEvidence(
        hasAnyDocument: true,
        hasServerConfirmedDocument: true,
        hasRetryableFailure: true,
        hasNetworkFailure: true,
      );
      expect(evidence.connectivity, ConnectivityState.offline);
    });

    test('a confirmation from the server means online', () {
      const evidence = ConnectionEvidence(
        hasAnyDocument: true,
        hasServerConfirmedDocument: true,
      );
      expect(evidence.connectivity, ConnectivityState.online);
    });

    test('documents held only from cache mean offline', () {
      const evidence = ConnectionEvidence(
        hasAnyDocument: true,
        hasServerConfirmedDocument: false,
      );
      expect(evidence.connectivity, ConnectivityState.offline);
    });
  });

  group('Synchronization derivation', () {
    test('a permanent refusal is blocked, not failed', () {
      const evidence = ConnectionEvidence(
        hasBlockedWrite: true,
        hasRetryableFailure: true,
        isSyncing: true,
        hasPendingWrites: true,
      );
      expect(evidence.synchronization, SynchronizationState.blocked);
    });

    test('a retryable failure is failed', () {
      const evidence = ConnectionEvidence(
        hasRetryableFailure: true,
        isSyncing: true,
        hasPendingWrites: true,
      );
      expect(evidence.synchronization, SynchronizationState.failed);
    });

    test('an in-flight run is syncing', () {
      const evidence = ConnectionEvidence(
        isSyncing: true,
        hasPendingWrites: true,
      );
      expect(evidence.synchronization, SynchronizationState.syncing);
    });

    test('an unacknowledged write is pending', () {
      const evidence = ConnectionEvidence(hasPendingWrites: true);
      expect(evidence.synchronization, SynchronizationState.pending);
    });

    test('nothing queued and nothing failed is idle', () {
      expect(
        ConnectionEvidence.none.synchronization,
        SynchronizationState.idle,
      );
    });
  });

  group('Status composition', () {
    test('only a confirmed-and-idle connection is nominal', () {
      expect(
        const ConnectionEvidence(
          hasServerConfirmedDocument: true,
        ).status().isNominal,
        isTrue,
      );
      expect(ConnectionStatus.unknown.isNominal, isFalse);
      expect(
        const ConnectionEvidence(
          hasServerConfirmedDocument: true,
          hasPendingWrites: true,
        ).status().isNominal,
        isFalse,
      );
    });

    test('a blocked write is reported as blocked, not as retrying', () {
      final status = const ConnectionEvidence(
        hasServerConfirmedDocument: true,
        hasBlockedWrite: true,
      ).status();
      expect(status.isBlocked, isTrue);
      expect(status.isRetrying, isFalse);
      expect(status.hasUnsyncedChanges, isFalse);
    });

    test('pending and syncing both count as unsynchronized changes', () {
      expect(
        const ConnectionEvidence(
          hasPendingWrites: true,
        ).status().hasUnsyncedChanges,
        isTrue,
      );
      expect(
        const ConnectionEvidence(isSyncing: true).status().hasUnsyncedChanges,
        isTrue,
      );
    });
  });

  group('Recovery history', () {
    const online = ConnectionEvidence(
      hasAnyDocument: true,
      hasServerConfirmedDocument: true,
    );
    // Confirmed, but a write is still being retried: the backend is reachable
    // and there is genuinely something to catch up on.
    const onlineRetrying = ConnectionEvidence(
      hasAnyDocument: true,
      hasServerConfirmedDocument: true,
      hasRetryableFailure: true,
    );
    const offline = ConnectionEvidence(hasAnyDocument: true);

    test('offline is remembered so the reconnection can be reported', () {
      var recovery = const ConnectionRecovery().observe(offline);
      expect(recovery.wasOffline, isTrue);
      expect(recovery.state, RecoveryState.notAttempted);

      recovery = recovery.observe(onlineRetrying);
      expect(recovery.state, RecoveryState.inProgress);
      expect(recovery.wasOffline, isTrue);
    });

    test('a settled reconnection is reported once, then forgotten', () {
      var recovery = const ConnectionRecovery()
          .observe(offline)
          .observe(onlineRetrying);
      expect(recovery.state, RecoveryState.inProgress);

      // The queued write lands: nothing is left to catch up on.
      recovery = recovery.observe(online);
      expect(recovery.state, RecoveryState.recovered);
      expect(recovery.wasOffline, isFalse);

      // And a later idle moment is not another reconnection.
      recovery = recovery.observe(online);
      expect(recovery.state, RecoveryState.recovered);
    });

    test('a permanent refusal survives the reconnection', () {
      const blockedOnline = ConnectionEvidence(
        hasAnyDocument: true,
        hasServerConfirmedDocument: true,
        hasBlockedWrite: true,
      );
      final recovery = const ConnectionRecovery()
          .observe(offline)
          .observe(blockedOnline);
      expect(recovery.state, RecoveryState.blocked);
      expect(recovery.wasOffline, isTrue);
    });

    test('no evidence leaves the history untouched', () {
      const settled = ConnectionRecovery();
      expect(
        settled.observe(ConnectionEvidence.none).state,
        RecoveryState.notAttempted,
      );
    });
  });
}
