import 'dart:async';

/// Coalesces bursts of local changes into one deferred action.
///
/// Device signals change in bursts (a screen toggle, a network flap, a charging
/// transition). Without coalescing each burst would become its own Firestore
/// write, which wastes quota and produces a partner-visible stutter
/// (Phase 11 §8, §29).
abstract interface class SyncScheduler {
  /// Runs [action] after [delay], replacing any action that is still pending.
  void schedule(Duration delay, void Function() action);

  /// Cancels any pending action.
  void cancel();

  /// Whether an action is currently pending.
  bool get hasPending;
}

/// The production scheduler, backed by a real timer.
class TimerSyncScheduler implements SyncScheduler {
  Timer? _timer;

  @override
  bool get hasPending => _timer?.isActive ?? false;

  @override
  void schedule(Duration delay, void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      action();
    });
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// A scheduler that runs the action synchronously, for deterministic tests.
class ImmediateSyncScheduler implements SyncScheduler {
  bool _pending = false;

  @override
  bool get hasPending => _pending;

  @override
  void schedule(Duration delay, void Function() action) {
    _pending = true;
    action();
    _pending = false;
  }

  @override
  void cancel() => _pending = false;
}
