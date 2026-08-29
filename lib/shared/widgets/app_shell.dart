import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/router/app_router.dart';

/// Premium navigation shell wrapping the main tab routes.
///
/// Five destinations: Home, Journey, Contacts, Activity, Settings.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _indexFor(location);

    return Scaffold(
      backgroundColor: AppTheme.navyBase,
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.navySurface,
          border: Border(
            top: BorderSide(
              color: AppTheme.glassBorder,
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) =>
              context.go(_destinationFor(index)),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route),
              label: 'Journey',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  int _indexFor(String location) {
    if (location.startsWith(AppRoutes.contacts)) return 2;
    if (location == AppRoutes.journey) return 1;
    if (location == AppRoutes.history) return 3;
    if (location == AppRoutes.settings) return 4;
    return 0;
  }

  String _destinationFor(int index) {
    return switch (index) {
      1 => AppRoutes.journey,
      2 => AppRoutes.contacts,
      3 => AppRoutes.history,
      4 => AppRoutes.settings,
      _ => AppRoutes.home,
    };
  }
}
