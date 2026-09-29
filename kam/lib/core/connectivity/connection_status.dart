/// Connectivity, synchronization and recovery semantics (Phase 20).
///
/// The application already models *data* availability (`DataAvailability`,
/// `CapabilityAvailability`) and *freshness* (`DataFreshness`). What was missing
/// is the ability to say anything true about the **connection** itself: whether
/// this device currently reaches the backend, whether its own writes have been
/// acknowledged, and whether a reconnection has finished recovering.
///
/// This model keeps those three questions separate, because collapsing them is
/// how "offline" starts meaning "the other person is unavailable":
///
/// ```text
/// connectivity     can we reach the backend at all?
/// synchronization  have our own writes been acknowledged?
/// recovery         has a reconnection finished flushing what was queued?
/// ```
///
/// Nothing here is an authorization signal. Being online is not permission, and
/// being offline is not permission denial: the Security Rules decide every read
/// and write, on every request (see docs/security/SECURITY_AND_AUTHORIZATION.md).
library;

/// Whether this device can currently reach the backend.
///
/// Derived from Firestore's own snapshot metadata (`isFromCache`,
/// `hasPendingWrites`) rather than a network probe, so it reports only what the
/// application can actually evidence.
enum ConnectivityState {
  /// At least one authoritative document has been confirmed by the server.
  online,

  /// Every authoritative document we hold is cache-served, or one of our writes
  /// is still queued: the backend is not currently reachable.
  offline,

  /// No evidence yet in this session. This is the honest state on a cold start
  /// before the first server confirmation — it is deliberately *not* "offline",
  /// because a first-load cache read says nothing about the connection.
  unknown,
}

/// Whether this device's own writes have reached the backend.
enum SynchronizationState {
  /// Nothing is queued and the last attempt did not fail.
  idle,

  /// A synchronization run is in flight.
  syncing,

  /// This device has a write the server has not acknowledged yet.
  pending,

  /// The backend refused the write for a reason that will not fix itself
  /// (`permission-denied`, `unauthenticated`, `invalid-argument`,
  /// `failed-precondition`). Retrying is pointless and is not attempted.
  blocked,

  /// The write failed for a reason that may fix itself (network, deadline,
  /// quota). A bounded retry with backoff is scheduled.
  failed,
}

/// The outcome of the most recent reconnection, when one happened.
///
/// Recovery is not a separate subsystem: Firestore resumes its listeners and
/// flushes queued writes on its own. This records what the *application*
/// observed, so the UI can say "catching up" instead of implying the data is
/// current.
enum RecoveryState {
  /// No reconnection has been attempted in this session.
  notAttempted,

  /// The connection returned and this device is catching up (queued writes or a
  /// synchronization run in flight).
  inProgress,

  /// The last reconnection finished with nothing left queued.
  recovered,

  /// Catching up cannot proceed because the backend refused the work.
  blocked,
}

/// A snapshot of the connection, as this device can evidence it.
class ConnectionStatus {
  const ConnectionStatus({
    required this.connectivity,
    required this.synchronization,
    this.recovery = RecoveryState.notAttempted,
  });

  /// Nothing is known yet. The safe default before any backend contact.
  static const ConnectionStatus unknown = ConnectionStatus(
    connectivity: ConnectivityState.unknown,
    synchronization: SynchronizationState.idle,
  );

  final ConnectivityState connectivity;
  final SynchronizationState synchronization;
  final RecoveryState recovery;

  bool get isOnline => connectivity == ConnectivityState.online;
  bool get isOffline => connectivity == ConnectivityState.offline;
  bool get isUnknown => connectivity == ConnectivityState.unknown;

  /// Whether there is nothing to report: the backend answered and nothing is
  /// waiting to be sent. Used to keep the connection indicator silent while
  /// everything is nominal (Phase 20 §26).
  bool get isNominal =>
      connectivity == ConnectivityState.online &&
      synchronization == SynchronizationState.idle &&
      recovery == RecoveryState.notAttempted;

  /// Whether local changes are still waiting to reach the backend.
  bool get hasUnsyncedChanges =>
      synchronization == SynchronizationState.pending ||
      synchronization == SynchronizationState.syncing;

  /// Whether the backend refused work for a permanent reason.
  bool get isBlocked =>
      synchronization == SynchronizationState.blocked ||
      recovery == RecoveryState.blocked;

  /// Whether the last attempt failed for a reason that may fix itself.
  bool get isRetrying => synchronization == SynchronizationState.failed;

  ConnectionStatus copyWith({
    ConnectivityState? connectivity,
    SynchronizationState? synchronization,
    RecoveryState? recovery,
  }) => ConnectionStatus(
    connectivity: connectivity ?? this.connectivity,
    synchronization: synchronization ?? this.synchronization,
    recovery: recovery ?? this.recovery,
  );

  @override
  String toString() =>
      'ConnectionStatus(${connectivity.name}, ${synchronization.name}, '
      'recovery: ${recovery.name})';
}

/// The evidence the connection status is derived from.
///
/// Every field is something the application can actually observe: Firestore
/// snapshot metadata, the outcome of a write it attempted, and whether its own
/// synchronization is in flight. Nothing is inferred from the *absence* of data
/// — "no news" is [ConnectivityState.unknown], never [ConnectivityState.offline],
/// which is exactly what keeps `offline ≠ powered off` true (Phase 20 §9).
class ConnectionEvidence {
  const ConnectionEvidence({
    this.hasAnyDocument = false,
    this.hasServerConfirmedDocument = false,
    this.hasPendingWrites = false,
    this.isSyncing = false,
    this.hasRetryableFailure = false,
    this.hasNetworkFailure = false,
    this.hasBlockedWrite = false,
  });

  /// No evidence at all: a cold start, or a build without Firebase.
  static const ConnectionEvidence none = ConnectionEvidence();

  /// Whether any authoritative document is held at all (a pair membership or a
  /// partner state document).
  final bool hasAnyDocument;

  /// Whether at least one held document was confirmed by the server
  /// (`isFromCache == false`).
  final bool hasServerConfirmedDocument;

  /// Whether this device holds one of its own writes that the server has not
  /// acknowledged. This is definitive: a queued write means the backend is not
  /// currently reachable.
  final bool hasPendingWrites;

  /// Whether a synchronization run is in flight right now.
  final bool isSyncing;

  /// Whether the last run failed for a reason that may fix itself.
  final bool hasRetryableFailure;

  /// Whether that failure was a network-level one (Firebase unreachable).
  ///
  /// Kept separate from [hasRetryableFailure] because `deadline-exceeded` or an
  /// unrecognised code is a failure, but is not evidence that the device is
  /// offline.
  final bool hasNetworkFailure;

  /// Whether the backend refused the last write permanently.
  final bool hasBlockedWrite;

  /// What this evidence says about reaching the backend.
  ConnectivityState get connectivity {
    if (hasPendingWrites) return ConnectivityState.offline;
    if (hasNetworkFailure) return ConnectivityState.offline;
    if (hasServerConfirmedDocument) return ConnectivityState.online;
    if (hasAnyDocument) return ConnectivityState.offline;
    return ConnectivityState.unknown;
  }

  /// What this evidence says about this device's own writes.
  SynchronizationState get synchronization {
    if (hasBlockedWrite) return SynchronizationState.blocked;
    if (hasRetryableFailure) return SynchronizationState.failed;
    if (isSyncing) return SynchronizationState.syncing;
    if (hasPendingWrites) return SynchronizationState.pending;
    return SynchronizationState.idle;
  }

  /// The full status, given the session's recovery history.
  ///
  /// [recovery] cannot be derived from a single moment — it describes a
  /// reconnection that already happened — so the caller that tracks transitions
  /// supplies it.
  ConnectionStatus status({
    RecoveryState recovery = RecoveryState.notAttempted,
  }) => ConnectionStatus(
    connectivity: connectivity,
    synchronization: synchronization,
    recovery: recovery,
  );
}

/// The session's reconnection history.
///
/// [ConnectionEvidence] describes one moment, so it cannot answer "did the
/// connection just come back?". That question needs a memory of the previous
/// moment, which is all this class adds — deliberately kept out of the evidence
/// so the derivation itself stays a pure function of what is observable now.
class ConnectionRecovery {
  const ConnectionRecovery({
    this.wasOffline = false,
    this.state = RecoveryState.notAttempted,
  });

  /// Whether this session has observed the backend being unreachable.
  final bool wasOffline;

  /// What the most recent reconnection is doing.
  final RecoveryState state;

  /// Applies a new moment of [evidence], producing the next history.
  ConnectionRecovery observe(ConnectionEvidence evidence) {
    switch (evidence.connectivity) {
      case ConnectivityState.offline:
        // Remember it, but say nothing about catching up: there is nothing to
        // catch up on until the connection actually returns.
        return const ConnectionRecovery(
          wasOffline: true,
          state: RecoveryState.notAttempted,
        );
      case ConnectivityState.online when wasOffline:
        if (evidence.hasBlockedWrite) {
          // A permanent refusal survives the reconnection: the work will never
          // be accepted, so recovery is blocked rather than in progress.
          return const ConnectionRecovery(
            wasOffline: true,
            state: RecoveryState.blocked,
          );
        }
        if (evidence.hasRetryableFailure ||
            evidence.hasPendingWrites ||
            evidence.isSyncing) {
          return const ConnectionRecovery(
            wasOffline: true,
            state: RecoveryState.inProgress,
          );
        }
        // Settled. Forgetting that we were offline is what stops every later
        // idle moment from being reported as a finished reconnection.
        return const ConnectionRecovery(state: RecoveryState.recovered);
      case ConnectivityState.online:
      case ConnectivityState.unknown:
        return this;
    }
  }

  @override
  String toString() =>
      'ConnectionRecovery(wasOffline: $wasOffline, state: ${state.name})';
}
