import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_scaffold.dart';

/// Placeholder for the trusted emergency contacts feature.
///
/// Phase 0 only. Contact management is implemented in a later phase.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureScaffold(
      title: 'Trusted Contacts',
      icon: Icons.people_outline,
      description: 'Trusted emergency contacts will be implemented in a later phase.',
    );
  }
}