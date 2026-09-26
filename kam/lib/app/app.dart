import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// The root widget of the application.
///
/// [router] can be injected so tests can start the app at a specific route
/// without going through the real bootstrap (SRS NFR-018).
class KamApp extends StatelessWidget {
  const KamApp({super.key, required this.config, this.router});

  /// Resolved compile-time configuration.
  final AppConfig config;

  /// Optional router override, primarily for tests.
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Know About Me',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router ?? createAppRouter(),
    );
  }
}
