import 'package:flutter/material.dart';

/// Placeholder privacy policy page. The full text is added when the product
/// and legal copy are finalized.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.privacy_tip_outlined,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Privacy policy', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'The privacy policy will be published here before release.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}