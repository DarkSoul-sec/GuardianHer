import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the user profile feature.
///
/// Phase 0 only. Profile management is implemented in a later phase.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Profile',
      icon: Icons.person_outline,
      description: 'User profile management will be implemented in a later phase.',
    );
  }
}