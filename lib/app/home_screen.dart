import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router/app_router.dart';

/// Home dashboard shown inside the app shell.
///
/// Lists the feature entry points not reachable from the navigation bar.
/// Phase 0: navigation only, no business logic.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const features = <({String title, IconData icon, String route})>[
      (title: 'SOS', icon: Icons.sos, route: AppRoutes.sos),
      (title: 'Location', icon: Icons.location_on_outlined, route: AppRoutes.location),
      (title: 'Authentication', icon: Icons.lock_outline, route: AppRoutes.auth),
      (title: 'Profile', icon: Icons.person_outline, route: AppRoutes.profile),
      (title: 'Permissions', icon: Icons.security_outlined, route: AppRoutes.permissions),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('GuardianHer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final feature in features)
            Card(
              child: ListTile(
                leading: Icon(feature.icon),
                title: Text(feature.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(feature.route),
              ),
            ),
        ],
      ),
    );
  }
}