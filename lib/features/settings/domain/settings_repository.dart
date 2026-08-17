import 'app_lock_delay.dart';
import 'security_settings.dart';

/// Persistence contract for non-sensitive security settings.
abstract interface class SettingsRepository {
  Future<SecuritySettings> loadSettings();
  Future<void> saveBiometricEnabled(bool enabled);
  Future<void> saveLockDelay(AppLockDelay delay);
}