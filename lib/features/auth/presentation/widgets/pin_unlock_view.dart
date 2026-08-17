import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/app_lock_providers.dart';
import '../../application/app_lock_state.dart';
import '../../domain/app_lock_failures.dart';
import 'pin_field.dart';
import 'reset_lock.dart';

/// Unlock form: PIN entry with a biometric shortcut and a recovery path.
class PinUnlockView extends ConsumerStatefulWidget {
  const PinUnlockView({super.key, required this.state});

  final AppLockState state;

  @override
  ConsumerState<PinUnlockView> createState() => _PinUnlockViewState();
}

class _PinUnlockViewState extends ConsumerState<PinUnlockView> {
  final _pinController = TextEditingController();

  bool _submitting = false;
  String? _error;
  Duration _remaining = Duration.zero;
  Timer? _countdown;

  AppLockState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _remaining = _state.lockoutRemaining;
    _syncCountdown();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _syncCountdown() {
    _countdown?.cancel();
    if (_remaining > Duration.zero) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = _remaining - const Duration(seconds: 1);
        if (next <= Duration.zero) {
          _countdown?.cancel();
          setState(() => _remaining = Duration.zero);
        } else {
          setState(() => _remaining = next);
        }
      });
    }
  }

  String _formatCountdown(Duration d) {
    final seconds = d.inSeconds;
    if (seconds >= 60) {
      return '${seconds ~/ 60}m ${seconds % 60}s';
    }
    return '${seconds}s';
  }

  Future<void> _unlockWithPin() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref
        .read(appLockControllerProvider.notifier)
        .unlockWithPin(_pinController.text);

    if (!mounted) return;
    setState(() {
      _submitting = false;
    });
    switch (result) {
      case Ok():
        return; // Redirected by the router.
      case Err(:final failure):
        _error = failure.message;
        _pinController.clear();
        if (failure is LockedOutFailure) {
          _remaining = failure.remaining;
          _syncCountdown();
        }
    }
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .unlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _submitting = false;
    });
    if (result case Err(:final failure)) {
      _error = failure.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(securitySettingsControllerProvider);
    final biometricEnabled = settings.biometricEnabled && _state.biometricsAvailable;
    final lockedOut = _remaining > Duration.zero;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Enter your PIN',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 32),
        PinField(
          controller: _pinController,
          label: 'PIN',
          autofocus: true,
          enabled: !lockedOut,
          onSubmitted: (_) => lockedOut ? null : _unlockWithPin(),
        ),
        if (lockedOut) ...[
          const SizedBox(height: 16),
          Text(
            'Too many incorrect attempts. Try again in ${_formatCountdown(_remaining)}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        if (_error != null && !lockedOut) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_submitting || lockedOut) ? null : _unlockWithPin,
          child: const Text('Unlock'),
        ),
        if (biometricEnabled) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _submitting ? null : _unlockWithBiometrics,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Use biometrics'),
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => confirmAndResetLock(context, ref),
          child: const Text('Forgot PIN?'),
        ),
      ],
    );
  }
}