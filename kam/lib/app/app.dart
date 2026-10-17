import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/platform/device_platform.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/device_state/presentation/providers/connection_providers.dart';
import '../features/device_state/presentation/providers/device_state_providers.dart';
import '../features/device_state/presentation/providers/device_monitoring_lifecycle.dart';
import '../features/device_state/presentation/providers/sync_providers.dart';
import '../features/pairing/presentation/providers/pairing_providers.dart';
import '../features/privacy/domain/models/sharing_category.dart';
import '../features/history/presentation/history_providers.dart';
import '../features/notifications/presentation/providers/notification_delivery_providers.dart';
import 'providers.dart';

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
    // Keep the authorized partner listener alive for the app runtime, even
    // when the dashboard route is not currently selected.
    ref.watch(partnerDeviceStateProvider);
    ref.watch(historyEventListenersProvider);
    // Notification delivery is mounted here, not in a screen, so a matched rule
    // can reach the user from any branch of the app.
    ref.watch(notificationDeliveryProvider);

    return DeviceMonitoringLifecycle(
      controller: ref.watch(deviceMonitoringControllerProvider),
      activityCollector: ref.watch(activityStateCollectorProvider),
      keepNativeMonitoringInBackground:
          ref.watch(platformInfoProvider).platform == DevicePlatform.android,
      onResume: () {
        // Recompute the connection from the latest evidence already held, and
        // give a queued or failed publish another trigger. Neither action
        // creates a listener, so resuming can never duplicate one
        // (Phase 20 §20, §21).
        ref.read(connectionStatusProvider.notifier).refresh();
        ref.read(deviceStateSyncCoordinatorProvider)?.reassertLatest();
        unawaited(_resumeLocationMonitoring(ref));
        unawaited(_reconcilePartnerFromServer(ref));
      },
      onBackground: () async {
        // Collect the current state (including the display state) and publish it
        // now, before the process can be suspended. Coalesced writes are
        // timer-driven and would otherwise be lost while the app is backgrounded,
        // which is why a screen turning off never reached the partner.
        try {
          final snapshot = await ref
              .read(deviceMonitoringControllerProvider)
              .collectNow();
          await ref
              .read(deviceStateSyncCoordinatorProvider)
              ?.publishNow(snapshot);
        } finally {
          // Location stays foreground-only even though Android keeps the
          // battery/network/display event subscriptions active in background.
          await ref.read(locationStateCollectorProvider).stop();
        }
      },
      onBackgroundError: (error, stackTrace) {
        ref
            .read(loggerProvider)
            .warning(
              'BACKGROUND_STATE_RECONCILIATION_FAILED',
              error: error,
              stackTrace: stackTrace,
              context: {'errorType': error.runtimeType.toString()},
            );
      },
      onPeriodicSync: () async {
        final snapshot = await ref
            .read(deviceMonitoringControllerProvider)
            .collectNow();
        await ref
            .read(deviceStateSyncCoordinatorProvider)
            ?.reconcileNow(snapshot);
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

Future<void> _resumeLocationMonitoring(WidgetRef ref) async {
  try {
    await ref.read(locationStateCollectorProvider).start();
  } catch (error, stackTrace) {
    ref
        .read(loggerProvider)
        .warning(
          'RESUME_LOCATION_MONITORING_FAILED',
          error: error,
          stackTrace: stackTrace,
          context: {'errorType': error.runtimeType.toString()},
        );
  }
}

Future<void> _reconcilePartnerFromServer(WidgetRef ref) async {
  try {
    final scope = ref.read(partnerScopeProvider).value;
    final sharing = ref.read(partnerSharingProvider).value;
    final repository = ref.read(partnerDeviceStateRepositoryProvider);
    if (scope == null || sharing == null || repository == null) return;
    if (!sharing.sharesAnyDeviceState &&
        !sharing.shares(SharingCategory.location)) {
      return;
    }

    await repository
        .readFromServer(
          pairId: scope.pairId,
          partnerUserId: scope.partnerUserId,
          watchDeviceState: sharing.sharesAnyDeviceState,
          watchLocation: sharing.shares(SharingCategory.location),
        )
        .timeout(const Duration(seconds: 10));

    // The server get warms Firestore's local cache. Restart the root listener
    // so it emits that value and then the server-confirmed snapshot.
    ref.invalidate(partnerDeviceStateProvider);
  } on TimeoutException {
    // The existing listener and cached value remain usable; next resume retries.
  } catch (error, stackTrace) {
    ref
        .read(loggerProvider)
        .warning(
          'RESUME_PARTNER_RECONCILIATION_FAILED',
          error: error,
          stackTrace: stackTrace,
          context: {'errorType': error.runtimeType.toString()},
        );
  }
}
