import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the settings feature.
///
/// Phase 0 only. Settings are implemented in a later phase.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Settings',
      icon: Icons.settings_outlined,
      description: 'Application settings will be implemented in a later phase.',
    );
  }
}