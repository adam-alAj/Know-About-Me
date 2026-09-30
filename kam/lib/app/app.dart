import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/device_state/presentation/providers/connection_providers.dart';
import '../features/device_state/presentation/providers/device_state_providers.dart';
import '../features/device_state/presentation/providers/device_monitoring_lifecycle.dart';
import '../features/device_state/presentation/providers/sync_providers.dart';
import '../features/history/presentation/history_providers.dart';
import '../features/notifications/presentation/providers/notification_delivery_providers.dart';

/// The root widget of the application.
///
/// The router comes from [appRouterProvider] so that the authentication guard is
/// part of the real application rather than something tests or `main()` assemble
/// separately. [router] remains as an explicit escape hatch for a test that needs
/// a router nobody else can produce.
class KamApp extends ConsumerWidget {
  const KamApp({super.key, required this.config, this.router});

  /// Resolved compile-time configuration.
  final AppConfig config;

  /// Optional router override.
  final GoRouter? router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instantiated at the root so real-time synchronization lives exactly as
    // long as the application does, and so its listeners are disposed with the
    // app rather than with one screen. It is inert without an active pair.
    ref.watch(deviceStateSyncCoordinatorProvider);
    ref.watch(historyEventListenersProvider);
    // Notification delivery is mounted here, not in a screen, so a matched rule
    // can reach the user from any branch of the app.
    ref.watch(notificationDeliveryProvider);

    return DeviceMonitoringLifecycle(
      controller: ref.watch(deviceMonitoringControllerProvider),
      activityCollector: ref.watch(activityStateCollectorProvider),
      onResume: () {
        // Recompute the connection from the latest evidence already held, and
        // give a queued or failed publish another trigger. Neither action
        // creates a listener, so resuming can never duplicate one
        // (Phase 20 §20, §21).
        ref.read(connectionStatusProvider.notifier).refresh();
        ref.read(deviceStateSyncCoordinatorProvider)?.reassertLatest();
      },
      onBackground: () async {
        // Collect the current state (including the display state) and publish it
        // now, before the process can be suspended. Coalesced writes are
        // timer-driven and would otherwise be lost while the app is backgrounded,
        // which is why a screen turning off never reached the partner.
        final snapshot = await ref
            .read(deviceMonitoringControllerProvider)
            .collectNow();
        await ref.read(deviceStateSyncCoordinatorProvider)?.publishNow(snapshot);
      },
      child: MaterialApp.router(
        title: 'Know About Me',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router ?? ref.watch(appRouterProvider),
      ),
    );
  }
}
