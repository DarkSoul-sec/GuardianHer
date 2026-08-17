import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/result/result.dart';
import '../../../shared/widgets/settings_section_header.dart';
import '../../auth/application/app_lock_providers.dart';
import '../../auth/domain/app_lock_status.dart';
import '../application/settings_providers.dart';
import '../domain/app_lock_delay.dart';

/// Security settings: app lock status, PIN change, biometric toggle, lock
/// delay and the reset/recovery path.
class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockControllerProvider);
    final settings = ref.watch(securitySettingsControllerProvider);
    final pinSet = lock.status != AppLockStatus.needsSetup;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: Text(pinSet ? 'PIN protected' : 'No PIN set'),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change PIN'),
            subtitle: const Text('Requires your current PIN'),
            enabled: pinSet,
            trailing: const Icon(Icons.chevron_right),
            onTap: pinSet ? () => context.push(AppRoutes.changePin) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            subtitle: Text(
              lock.biometricsAvailable
                  ? 'Unlock with biometrics when available'
                  : 'Biometrics are not available on this device',
            ),
            value: settings.biometricEnabled,
            onChanged: lock.biometricsAvailable
                ? (value) => _toggleBiometrics(context, ref, value)
                : null,
          ),
          const SettingsSectionHeader(title: 'Lock after leaving the app'),
          RadioGroup<AppLockDelay>(
            groupValue: settings.lockDelay,
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(securitySettingsControllerProvider.notifier)
                    .setLockDelay(value);
              }
            },
            child: Column(
              children: [
                for (final delay in AppLockDelay.values)
                  RadioListTile<AppLockDelay>(
                    title: Text(delay.label),
                    value: delay,
                  ),
              ],
            ),
          ),
          const SettingsSectionHeader(title: 'Recovery'),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset app lock'),
            subtitle: const Text('Verify your identity, then set up a new PIN'),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometrics(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(securitySettingsControllerProvider.notifier)
        .setBiometricEnabled(value);
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// Resets the app lock only after verifying the user's identity: biometrics
  /// when enabled and available, otherwise the current PIN. The reset is a
  /// soft reset that preserves all other local data.
  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(appLockControllerProvider.notifier);
    final lock = ref.read(appLockControllerProvider);
    final settings = ref.read(securitySettingsControllerProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset app lock?'),
        content: const Text(
          'Verify your identity with biometrics or your current PIN. Your PIN '
          'will be removed and you will be asked to set a new one. Your other '
          'data is kept.',
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

    var verified = false;
    final biometricEnabled =
        settings.biometricEnabled && lock.biometricsAvailable;
    if (biometricEnabled) {
      final result = await controller.verifyBiometric(
        reason: 'Verify your identity to reset the app lock',
      );
      verified = result is Ok<bool> && result.value;
    }
    if (!verified) {
      if (!context.mounted) return;
      verified = await _verifyCurrentPin(context, ref);
    }

    if (!verified) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Reset cancelled: identity not verified.')),
      );
      return;
    }

    final result = await controller.resetLock();
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// Prompts for the current PIN and verifies it against the app lock.
  Future<bool> _verifyCurrentPin(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(appLockControllerProvider.notifier);
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => const CurrentPinDialog(),
    );
    if (entered == null) return false;
    final result = await controller.unlockWithPin(entered);
    return result is Ok;
  }
}

/// Modal dialog that collects the current PIN for identity verification.
class CurrentPinDialog extends StatefulWidget {
  const CurrentPinDialog({super.key});

  @override
  State<CurrentPinDialog> createState() => _CurrentPinDialogState();
}

class _CurrentPinDialogState extends State<CurrentPinDialog> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your current PIN'),
      content: TextField(
        controller: _pinController,
        obscureText: true,
        keyboardType: TextInputType.number,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pinController.text),
          child: const Text('Verify'),
        ),
      ],
    );
  }
}