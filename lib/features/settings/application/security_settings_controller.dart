import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/biometric_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../domain/app_lock_delay.dart';
import '../domain/security_settings.dart';
import '../domain/settings_failures.dart';
import '../domain/settings_repository.dart';
import 'settings_providers.dart';

/// Owns the non-sensitive security settings (biometric toggle, lock delay).
class SecuritySettingsController extends Notifier<SecuritySettings> {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);
  BiometricService get _biometrics => ref.read(biometricServiceProvider);

  @override
  SecuritySettings build() {
    _load();
    return const SecuritySettings();
  }

  Future<void> _load() async {
    final settings = await _repository.loadSettings();
    state = settings;
  }

  /// Enables or disables biometric unlock. Enabling requires a successful
  /// biometric verification first.
  Future<Result<void>> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      if (!await _biometrics.isAvailable()) {
        return const Err(BiometricSetupFailure());
      }
      final result = await _biometrics.authenticate(
        reason: 'Verify your identity to enable biometric unlock',
      );
      if (result is Err<bool>) return Err(result.failure);
      if (result is Ok<bool> && !result.value) {
        return const Err(BiometricSetupFailure());
      }
    }
    await _repository.saveBiometricEnabled(enabled);
    state = state.copyWith(biometricEnabled: enabled);
    return const Ok<void>(null);
  }

  Future<Result<void>> setLockDelay(AppLockDelay delay) async {
    await _repository.saveLockDelay(delay);
    state = state.copyWith(lockDelay: delay);
    return const Ok<void>(null);
  }
}