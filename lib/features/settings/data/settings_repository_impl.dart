import '../../../core/platform/preferences_service.dart';
import '../domain/app_lock_delay.dart';
import '../domain/security_settings.dart';
import '../domain/settings_repository.dart';

/// Keys used to persist security settings in preferences.
abstract final class SettingsStorageKeys {
  SettingsStorageKeys._();

  static const biometricEnabled = 'settings_biometric_enabled';
  static const lockDelay = 'settings_lock_delay';
}

/// Stores non-sensitive security settings in preferences.
class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl({required this.preferences});

  final PreferencesService preferences;

  @override
  Future<SecuritySettings> loadSettings() async {
    final biometricEnabled =
        await preferences.getBool(SettingsStorageKeys.biometricEnabled) ??
            false;
    final lockDelay = AppLockDelay.fromStorage(
      await preferences.getString(SettingsStorageKeys.lockDelay),
    );
    return SecuritySettings(
      biometricEnabled: biometricEnabled,
      lockDelay: lockDelay,
    );
  }

  @override
  Future<void> saveBiometricEnabled(bool enabled) =>
      preferences.setBool(SettingsStorageKeys.biometricEnabled, enabled);

  @override
  Future<void> saveLockDelay(AppLockDelay delay) =>
      preferences.setString(SettingsStorageKeys.lockDelay, delay.storageValue);
}