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
/// one collection; inactive/paused/detached stops the stream promptly.
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

  /// Run once when the application leaves the foreground, *before* monitoring is
  /// released.
  ///
  /// This is where the last observed state is published immediately. The
  /// synchronization service normally coalesces writes over a short window via a
  /// timer, and a timer does not run while the process is suspended — so without
  /// this the final transition (a screen turning off, for example) was observed
  /// locally and then never reached the partner.
  final Future<void> Function()? onBackground;

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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.activityCollector?.reportAppLifecycle(appLifecyclePhaseOf(state));
    if (state == AppLifecycleState.resumed) {
      _lifecycleToken++;
      widget.controller.startMonitoring();
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
    unawaited(_captureFinalScreenStateThenStop(token));
  }

  Future<void> _captureFinalScreenStateThenStop(int token) async {
    // Read the whole current state and publish it immediately, before the
    // observers are released and before the process can be suspended. The
    // collectors re-read the display state here, so a screen-off transition at
    // the moment of backgrounding is captured and written straight away rather
    // than being left to a coalescing timer that will not fire while suspended.
    try {
      await widget.onBackground?.call();
    } catch (_) {
      // A failed publish must never block releasing the platform observers.
    }
    // A resume that happened while the publish was in flight has superseded this
    // stop; cancelling now would tear down the subscription it just started.
    if (token != _lifecycleToken) return;
    await widget.controller.stopMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
