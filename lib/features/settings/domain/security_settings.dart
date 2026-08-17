import 'app_lock_delay.dart';

/// Non-sensitive security settings.
class SecuritySettings {
  const SecuritySettings({
    this.biometricEnabled = false,
    this.lockDelay = AppLockDelay.immediate,
  });

  final bool biometricEnabled;
  final AppLockDelay lockDelay;

  SecuritySettings copyWith({bool? biometricEnabled, AppLockDelay? lockDelay}) {
    return SecuritySettings(
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      lockDelay: lockDelay ?? this.lockDelay,
    );
  }
}