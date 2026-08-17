import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/app_lock_providers.dart';

/// Exact warning shown before a destructive reset, when the user cannot verify
/// their identity. The user must explicitly confirm before local data is wiped.
const String kDestructiveResetWarning =
    'Without your existing PIN or biometric verification, resetting the app '
    'will permanently delete your locally stored data.';

/// Confirms and performs the app-lock reset.
///
/// Identity-verified path: when biometric unlock is enabled and available, the
/// user verifies with biometrics and the PIN is reset while all other data is
/// preserved.
///
/// Unverified path: without a successful identity check the reset is
/// destructive. [kDestructiveResetWarning] is shown and the user must
/// explicitly confirm before all local data is permanently deleted.
Future<void> confirmAndResetLock(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(appLockControllerProvider.notifier);
  final lock = ref.read(appLockControllerProvider);
  final settings = ref.read(securitySettingsControllerProvider);
  final biometricEnabled =
      settings.biometricEnabled && lock.biometricsAvailable;

  if (biometricEnabled) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset app lock?'),
        content: const Text(
          'Your identity will be verified with biometrics. Your PIN will be '
          'removed and you will be asked to set a new one. Your other data is '
          'kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await controller.verifyBiometric(
      reason: 'Verify your identity to reset the app lock',
    );
    if (result is Ok<bool> && result.value) {
      final reset = await controller.resetLock();
      if (reset case Err(:final failure)) {
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      }
      return;
    }
  }

  if (!context.mounted) return;

  final destructiveConfirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete your local data?'),
      content: const Text(kDestructiveResetWarning),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete & Reset'),
        ),
      ],
    ),
  );
  if (destructiveConfirmed != true) return;

  final result = await controller.destructiveReset();
  if (result case Err(:final failure)) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}