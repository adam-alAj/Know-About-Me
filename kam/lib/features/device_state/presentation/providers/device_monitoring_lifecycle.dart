import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/models/activity_state.dart';
import '../../domain/services/activity_state_collector.dart';
import '../../data/providers/platform_device_state_provider.dart';

/// Maps Flutter's own lifecycle onto the domain phases.
///
/// This describes **this application only** — never the display, never device
/// usage, never the person behind the phone.
AppLifecyclePhase appLifecyclePhaseOf(AppLifecycleState state) =>
    switch (state) {
      AppLifecycleState.resumed => AppLifecyclePhase.foreground,
      AppLifecycleState.inactive => AppLifecyclePhase.inactive,
      AppLifecycleState.hidden => AppLifecyclePhase.hidden,
      AppLifecycleState.paused => AppLifecyclePhase.background,
      AppLifecycleState.detached => AppLifecyclePhase.detached,
    };

/// Maps Flutter app lifecycle to best-effort monitoring commands. Resume does
/// one collection; Android keeps subscriptions on pause when configured, and
/// detach (or pause on other platforms) releases them after a final publish.
///
/// Each lifecycle transition is also reported to the optional
/// [activityCollector], which is the supported signal source for the
/// application-lifecycle part of Phase 9. Reports continue while monitoring
/// is stopped: a lifecycle push needs no native subscription, and an observed
/// transition is a real platform event.
class DeviceMonitoringLifecycle extends StatefulWidget {
  const DeviceMonitoringLifecycle({
    required this.controller,
    required this.child,
    this.activityCollector,
    this.onResume,
    this.onBackground,
    this.onBackgroundError,
    this.onPeriodicSync,
    this.keepNativeMonitoringInBackground = false,
    super.key,
  });
  final DeviceMonitoringController controller;
  final ActivityStateCollector? activityCollector;

  /// Optional hook run once per resume, after monitoring has restarted.
  ///
  /// Used to re-derive the connection state and to give an unfinished publish
  /// another trigger. It must not create subscriptions: a resumed application
  /// must never end up with two listeners for the same data (Phase 20 §20, §21).
  final VoidCallback? onResume;

  /// Run once when the application leaves the foreground, before any platform
  /// subscription is released.
  ///
  /// This is where the last observed state is published immediately. The
  /// synchronization service normally coalesces writes over a short window via a
  /// timer, and a timer does not run while the process is suspended — so without
  /// this the final transition (a screen turning off, for example) was observed
  /// locally and then never reached the partner.
  final Future<void> Function()? onBackground;

  /// Receives failures from the final background reconciliation so they can
  /// be reported without preventing subscription cleanup on platforms that
  /// stop monitoring in the background.
  final void Function(Object error, StackTrace stackTrace)? onBackgroundError;

  /// Best-effort foreground heartbeat. Mobile operating systems do not allow
  /// an app to keep a Dart timer running after suspension.
  final Future<void> Function()? onPeriodicSync;

  /// Keeps Android's event-driven platform subscriptions alive while the app
  /// is backgrounded. Android may still suspend or kill the process, so this
  /// does not provide continuous execution or keep Dart timers running.
  final bool keepNativeMonitoringInBackground;

  final Widget child;

  @override
  State<DeviceMonitoringLifecycle> createState() =>
      _DeviceMonitoringLifecycleState();
}

class _DeviceMonitoringLifecycleState extends State<DeviceMonitoringLifecycle>
    with WidgetsBindingObserver {
  /// Bumped on every lifecycle transition that changes what monitoring should
  /// be doing. A slow background read can then avoid tearing down a
  /// subscription that a following resume has just started.
  int _lifecycleToken = 0;
  Timer? _foregroundSyncTimer;
  bool _periodicSyncRunning = false;

  static const _foregroundSyncInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The initial state only establishes the current phase: an application
    // starting is not an observed activity event and never creates a
    // `lastObservedActivityAt` timestamp.
    final initial = WidgetsBinding.instance.lifecycleState;
    if (initial != null) {
      widget.activityCollector?.reportAppLifecycle(
        appLifecyclePhaseOf(initial),
      );
    }
    widget.controller.startMonitoring();
    _startForegroundSyncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.activityCollector?.reportAppLifecycle(appLifecyclePhaseOf(state));
    if (state == AppLifecycleState.resumed) {
      _lifecycleToken++;
      widget.controller.startMonitoring();
      _startForegroundSyncTimer();
      // A resumed app cannot assume a background listener or timer stayed
      // alive, so the connection is re-derived from fresh evidence and any
      // unfinished publish is re-requested (Phase 20 §20).
      widget.onResume?.call();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // `inactive` is a transient loss of focus — a system dialog, the
      // notification shade, the moments around the screen turning off — and
      // `hidden` is the transition immediately before `paused` on Android.
      // Releasing the observers on either would drop the very screen
      // transition the application is meant to report. `paused` is the settled
      // background state and is handled below.
      return;
    }
    // Publish the current state (including the display state) before releasing
    // the observers. This is event-driven, never a timer (Phase 9, FR-016).
    final token = ++_lifecycleToken;
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = null;
    unawaited(
      _captureFinalScreenStateThenStop(
        token,
        keepMonitoring:
            state == AppLifecycleState.paused &&
            widget.keepNativeMonitoringInBackground,
      ),
    );
  }

  Future<void> _captureFinalScreenStateThenStop(
    int token, {
    required bool keepMonitoring,
  }) async {
    // Read the whole current state and publish it immediately, before the
    // observers are released and before the process can be suspended. The
    // collectors re-read the display state here, so a screen-off transition at
    // the moment of backgrounding is captured and written straight away rather
    // than being left to a coalescing timer that will not fire while suspended.
    try {
      await widget.onBackground?.call();
    } catch (error, stackTrace) {
      // A failed publish must never block releasing the platform observers.
      widget.onBackgroundError?.call(error, stackTrace);
    }
    // A resume that happened while the publish was in flight has superseded this
    // stop; cancelling now would tear down the subscription it just started.
    if (token != _lifecycleToken) return;
    if (keepMonitoring) return;
    await widget.controller.stopMonitoring();
  }

  void _startForegroundSyncTimer() {
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = Timer.periodic(_foregroundSyncInterval, (_) {
      if (_periodicSyncRunning || !mounted) return;
      _periodicSyncRunning = true;
      unawaited(() async {
        try {
          await widget.onPeriodicSync?.call();
        } catch (_) {
          // A transient collection/write failure is retried by the next
          // lifecycle or periodic trigger; it must not escape the zone.
        } finally {
          _periodicSyncRunning = false;
        }
      }());
    });
  }

  @override
  void dispose() {
    _foregroundSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
