import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../application/app_lock_providers.dart';
import 'pin_field.dart';

/// First-launch PIN creation: create + confirm before the PIN is accepted.
class PinSetupView extends ConsumerStatefulWidget {
  const PinSetupView({super.key});

  @override
  ConsumerState<PinSetupView> createState() => _PinSetupViewState();
}

class _PinSetupViewState extends ConsumerState<PinSetupView> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref.read(appLockControllerProvider.notifier).setupPin(
          pin: _pinController.text,
          confirmation: _confirmController.text,
        );

    if (!mounted) return;
    if (result case Err(:final failure)) {
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shield_outlined, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Welcome to GuardianHer',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Create a 6-digit PIN to protect your app. '
          'It is stored securely and never in plaintext.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        PinField(
          controller: _pinController,
          label: 'Create PIN',
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        PinField(
          controller: _confirmController,
          label: 'Confirm PIN',
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Set PIN'),
        ),
      ],
    );
  }
}