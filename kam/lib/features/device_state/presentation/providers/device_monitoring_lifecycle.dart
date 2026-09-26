import 'package:flutter/widgets.dart';

import '../../data/providers/platform_device_state_provider.dart';

/// Maps Flutter app lifecycle to best-effort monitoring commands. Resume does
/// one collection; inactive/paused/detached stops the stream promptly.
class DeviceMonitoringLifecycle extends StatefulWidget {
  const DeviceMonitoringLifecycle({required this.controller, required this.child, super.key});
  final DeviceMonitoringController controller;
  final Widget child;

  @override
  State<DeviceMonitoringLifecycle> createState() => _DeviceMonitoringLifecycleState();
}

class _DeviceMonitoringLifecycleState extends State<DeviceMonitoringLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.startMonitoring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
