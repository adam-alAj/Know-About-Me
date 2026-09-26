import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/widgets/empty_view.dart';
import '../../core/ui/widgets/app_scaffold.dart';
import 'app_routes.dart';

/// Shown for a URL that matches no route.
class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({super.key, this.uri});

  /// The unmatched location, shown to aid development.
  final String? uri;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Not found',
      body: Column(
        children: [
          Expanded(
            child: EmptyView(
              icon: Icons.explore_off_outlined,
              title: 'Page not found',
              message: uri == null
                  ? 'That screen does not exist.'
                  : 'No screen matches "$uri".',
            ),
          ),
          TextButton(
            onPressed: () => context.goNamed(AppRoutes.dashboard),
            child: const Text('Back to reassurance'),
          ),
        ],
      ),
    );
  }
}
