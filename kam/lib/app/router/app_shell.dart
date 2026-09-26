import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The main application shell.
///
/// Provides the persistent bottom navigation so features can be added as
/// branches without each screen rebuilding navigation (SRS Task 6, Task 14).
/// The shell intentionally holds no business state.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  /// The branch navigator provided by `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    // Tapping the active destination returns to its initial route.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.rule_outlined),
            selectedIcon: Icon(Icons.rule),
            label: 'Rules',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Privacy',
          ),
        ],
      ),
    );
  }
}
