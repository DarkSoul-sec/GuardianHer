import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_lock_providers.dart';
import '../domain/app_lock_status.dart';
import 'widgets/corrupted_view.dart';
import 'widgets/pin_setup_view.dart';
import 'widgets/pin_unlock_view.dart';

/// Gates the entire app: shown whenever the app is not unlocked.
///
/// Renders PIN setup on first launch, PIN/biometric unlock when locked, and a
/// reset path when stored data is corrupted. The system back button cannot
/// leave the lock screen.
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockControllerProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: switch (state.status) {
                  AppLockStatus.unknown =>
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    ),
                  AppLockStatus.needsSetup => const PinSetupView(),
                  AppLockStatus.locked => PinUnlockView(state: state),
                  AppLockStatus.corrupted => const CorruptedView(),
                  AppLockStatus.unlocked => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}