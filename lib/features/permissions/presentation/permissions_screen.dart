import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the permissions management feature.
///
/// Phase 0 only. Centralized permission management is implemented in a later
/// phase using the [PermissionService] abstraction.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Permissions',
      icon: Icons.security_outlined,
      description: 'Centralized permission management will be implemented in a later phase.',
    );
  }
}