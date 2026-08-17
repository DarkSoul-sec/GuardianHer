import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reset_lock.dart';

/// Fail-closed state shown when stored authentication data is unreadable.
///
/// The app stays locked; the only way forward is to reset the app lock and
/// create a new PIN. Identity cannot be verified against the corrupted data,
/// so the reset is destructive and requires explicit confirmation.
class CorruptedView extends ConsumerWidget {
  const CorruptedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'Security data unavailable',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'The stored security data on this device could not be read. '
          'For your safety the app stays locked. You can reset the app lock '
          'and set a new PIN.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => confirmAndResetLock(context, ref),
          child: const Text('Reset app lock'),
        ),
      ],
    );
  }
}