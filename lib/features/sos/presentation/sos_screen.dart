import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the SOS emergency workflow feature.
///
/// Phase 0 only. The SOS workflow is implemented in a later phase.
class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'SOS',
      icon: Icons.sos,
      description: 'The SOS emergency workflow will be implemented in a later phase.',
    );
  }
}