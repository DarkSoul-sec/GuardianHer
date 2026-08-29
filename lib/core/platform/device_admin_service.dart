import 'package:flutter/services.dart';

/// Abstraction over Android's device-administrator status (user-opt-in).
///
/// While active, the system blocks uninstall and disables the "Force stop"
/// button for GuardianHer until the admin is deactivated, which keeps the
/// Shake SOS detector running and makes the app much harder to remove. No
/// device policies (lock/wipe) are used. On non-Android platforms this is
/// unsupported; the Settings screen hides the feature.
abstract interface class DeviceAdminService {
  /// Whether GuardianHer is currently an active device administrator.
  Future<bool> isActive();

  /// Opens the system activation screen if not yet active. Returns whether
  /// the app is active at the moment the method completes.
  Future<bool> requestActivation();

  /// Deactivates GuardianHer as a device administrator (re-enables uninstall
  /// and force-stop). Reversible by activating again.
  Future<void> deactivate();
}

/// Platform-channel implementation bound in [core/providers.dart].
class DeviceAdminServiceChannel implements DeviceAdminService {
  const DeviceAdminServiceChannel();

  static const MethodChannel _channel = MethodChannel('guardianher/device_admin');

  @override
  Future<bool> isActive() async =>
      await _channel.invokeMethod<bool>('isActive') ?? false;

  @override
  Future<bool> requestActivation() async =>
      await _channel.invokeMethod<bool>('requestActivation') ?? false;

  @override
  Future<void> deactivate() async {
    await _channel.invokeMethod<void>('deactivate');
  }
}