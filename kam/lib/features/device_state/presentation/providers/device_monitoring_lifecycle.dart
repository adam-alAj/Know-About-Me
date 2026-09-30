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
    if (state == AppLifecycleState.inactive) {
      // `inactive` is a transient loss of focus — a system dialog, the
      // notification shade, the moments around the screen turning off. It is
      // not backgrounding, and tearing the observers down here would drop the
      // very screen transition the application is meant to report. The
      // observers are released on `hidden`/`paused`/`detached` instead.
      return;
    }
    // One bounded read of the display state before releasing the observers, so
    // a screen-off transition at the moment of backgrounding is still observed
    // and published. This is event-driven, never a timer (Phase 9, FR-016).
    final token = ++_lifecycleToken;
    unawaited(_captureFinalScreenStateThenStop(token));
  }

  Future<void> _captureFinalScreenStateThenStop(int token) async {
    try {
      await widget.activityCollector?.refresh();
    } catch (_) {
      // A failed read must never block releasing the platform observers.
    }
    // A resume that happened while the read was in flight has superseded this
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
