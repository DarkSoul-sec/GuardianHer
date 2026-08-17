import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../auth/application/app_lock_providers.dart';
import '../../auth/domain/app_lock_failures.dart';
import '../../auth/presentation/widgets/pin_field.dart';

/// Changes the app lock PIN. The current PIN must be verified first.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref.read(appLockControllerProvider.notifier).changePin(
          currentPin: _currentController.text,
          newPin: _newController.text,
          confirmation: _confirmController.text,
        );

    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN changed')),
        );
      case Err(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message;
          if (failure is PinVerificationFailure) {
            _currentController.clear();
          }
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.password_outlined,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 24),
                    PinField(
                      controller: _currentController,
                      label: 'Current PIN',
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    PinField(
                      controller: _newController,
                      label: 'New PIN',
                    ),
                    const SizedBox(height: 16),
                    PinField(
                      controller: _confirmController,
                      label: 'Confirm new PIN',
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
                      child: const Text('Change PIN'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}