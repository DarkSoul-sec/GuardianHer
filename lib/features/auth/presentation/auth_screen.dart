import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the authentication feature.
///
/// Phase 0 only. Local PIN + biometric unlock is implemented in a later phase.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Authentication',
      icon: Icons.lock_outline,
      description: 'Local app unlock (PIN and biometrics) will be implemented '
          'in a later phase.',
    );
  }
}