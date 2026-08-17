import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the current GPS location feature.
///
/// Phase 0 only. Location access is implemented in a later phase.
class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Location',
      icon: Icons.location_on_outlined,
      description: 'Current GPS location will be implemented in a later phase.',
    );
  }
}