import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/device_state/presentation/providers/device_state_providers.dart';
import '../features/device_state/presentation/providers/device_monitoring_lifecycle.dart';

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
    return DeviceMonitoringLifecycle(
      controller: ref.watch(deviceMonitoringControllerProvider),
      activityCollector: ref.watch(activityStateCollectorProvider),
      child: MaterialApp.router(
        title: 'Know About Me',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router ?? ref.watch(appRouterProvider),
      ),
    );
  }
}
