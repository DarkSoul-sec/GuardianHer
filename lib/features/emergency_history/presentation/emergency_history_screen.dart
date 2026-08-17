import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the emergency event history feature.
///
/// Phase 0 only. Event history is implemented in a later phase.
class EmergencyHistoryScreen extends StatelessWidget {
  const EmergencyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Emergency History',
      icon: Icons.history_outlined,
      description: 'Emergency event history will be implemented in a later phase.',
    );
  }
}