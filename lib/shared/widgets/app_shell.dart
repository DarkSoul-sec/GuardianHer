import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/router/app_router.dart';

/// GuardianHer floating navigation shell.
///
/// Four primary destinations: Home, Map, Contacts, Profile.
/// Keeps the Material [NavigationBar] widget (pinned by widget tests) inside
/// a floating warm-white rounded container with a soft shadow.
/// Legacy routes (/journey, /history, /settings) stay registered and reachable
/// from Map/Profile screens; the tab bar highlights the owning section.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _indexFor(location);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.borderLight),
              boxShadow: AppTheme.softShadow(),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
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
                    icon: Icon(Icons.location_on_outlined),
                    selectedIcon: Icon(Icons.location_on),
                    label: 'Map',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: 'Contacts',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _indexFor(String location) {
    if (location.startsWith(AppRoutes.contacts)) return 2;
    if (location == AppRoutes.map || location == AppRoutes.journey) return 1;
    if (location == AppRoutes.profile ||
        location == AppRoutes.history ||
        location.startsWith(AppRoutes.settings)) {
      return 3;
    }
    return 0;
  }

  String _destinationFor(int index) {
    return switch (index) {
      1 => AppRoutes.map,
      2 => AppRoutes.contacts,
      3 => AppRoutes.profile,
      _ => AppRoutes.home,
    };
  }
}
