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
    super.key,
  });
  final DeviceMonitoringController controller;
  final ActivityStateCollector? activityCollector;
  final Widget child;

  @override
  State<DeviceMonitoringLifecycle> createState() =>
      _DeviceMonitoringLifecycleState();
}

class _DeviceMonitoringLifecycleState extends State<DeviceMonitoringLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The initial state only establishes the current phase: an application
    // starting is not an observed activity event and never creates a
    // `lastObservedActivityAt` timestamp.
    final initial = WidgetsBinding.instance.lifecycleState;
    if (initial != null) {
      widget.activityCollector?.reportAppLifecycle(appLifecyclePhaseOf(initial));
    }
    widget.controller.startMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.activityCollector?.reportAppLifecycle(appLifecyclePhaseOf(state));
    if (state == AppLifecycleState.resumed) {
      widget.controller.startMonitoring();
    } else {
      widget.controller.stopMonitoring();
    }
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
