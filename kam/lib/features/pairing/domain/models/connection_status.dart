/// Relationship status visible in the UI (SRS FR-006).
enum ConnectionStatus {
  notConnected,
  pairingPending,
  connectionRequested,
  connected,
  temporarilyPaused,
  disconnected,
  revoked,
}

/// The controlled lifecycle of a pair (SRS NFR-042).
///
/// Illegal transitions must be rejected; [PairLifecycleState.canTransitionTo]
/// encodes the allowed transitions so the rule lives in one place.
enum PairLifecycleState {
  created,
  requested,
  accepted,
  active,
  paused,
  revoked,
  disconnected;

  /// Whether this state may legally move to [next].
  bool canTransitionTo(PairLifecycleState next) {
    switch (this) {
      case PairLifecycleState.created:
        return next == PairLifecycleState.requested;
      case PairLifecycleState.requested:
        return next == PairLifecycleState.accepted ||
            next == PairLifecycleState.revoked;
      case PairLifecycleState.accepted:
        return next == PairLifecycleState.active ||
            next == PairLifecycleState.revoked;
      case PairLifecycleState.active:
        return next == PairLifecycleState.paused ||
            next == PairLifecycleState.revoked ||
            next == PairLifecycleState.disconnected;
      case PairLifecycleState.paused:
        return next == PairLifecycleState.active ||
            next == PairLifecycleState.revoked ||
            next == PairLifecycleState.disconnected;
      case PairLifecycleState.revoked:
      case PairLifecycleState.disconnected:
        return false;
    }
  }
}

/// The status a pair presents in [ConnectionStatus] terms.
extension ConnectionStatusFromLifecycle on PairLifecycleState {
  /// Maps the lifecycle state onto the user-facing connection status.
  ConnectionStatus get connectionStatus {
    switch (this) {
      case PairLifecycleState.created:
        return ConnectionStatus.notConnected;
      case PairLifecycleState.requested:
        return ConnectionStatus.connectionRequested;
      case PairLifecycleState.accepted:
        return ConnectionStatus.pairingPending;
      case PairLifecycleState.active:
        return ConnectionStatus.connected;
      case PairLifecycleState.paused:
        return ConnectionStatus.temporarilyPaused;
      case PairLifecycleState.revoked:
        return ConnectionStatus.revoked;
      case PairLifecycleState.disconnected:
        return ConnectionStatus.disconnected;
    }
  }
}
