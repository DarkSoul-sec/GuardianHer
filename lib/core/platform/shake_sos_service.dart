import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the native shake detector is available on this platform.
bool get isShakeSosSupported => defaultTargetPlatform == TargetPlatform.android;

/// Controls the native shake-detection foreground service (Android only).
///
/// When enabled, the service keeps the accelerometer stream alive even while
/// the app is closed, so a deliberate shake can arm SOS from anywhere. On
/// non-Android platforms the channel does not exist; callers guard with
/// [isShakeSosSupported].
abstract interface class ShakeSosService {
  /// Starts the background shake detector (persistent, with a notification).
  Future<void> start();

  /// Stops the background shake detector.
  Future<void> stop();

  /// Opens the device's battery-optimization settings page so the user can
  /// whitelist GuardianHer (required on Xiaomi/Redmi-style aggressive battery
  /// managers for the detector to survive).
  Future<void> openBatteryOptimizationSettings();

  /// Whether Android currently exempts GuardianHer from battery optimization
  /// (`PowerManager.isIgnoringBatteryOptimizations`). When false, stock
  /// Android and aggressive OEM managers may stop the detector.
  Future<bool> isIgnoringBatteryOptimizations();

  /// Stable token for this device's manufacturer family so the UI can show
  /// OEM-specific background guidance (e.g. `miui` for Xiaomi/Redmi/POCO,
  /// `coloros` for Oppo/OnePlus/realme, `emui` for Huawei). Null when the
  /// maker needs no special wording.
  Future<String?> manufacturerToken();

  /// Whether the user has granted the "Display over other apps"
  /// (`SYSTEM_ALERT_WINDOW`) permission. This is what lets a detected shake
  /// bring the app to the foreground when it is fully closed; without it
  /// Android silently blocks the launch (`BAL_BLOCK`).
  Future<bool> canDrawOverlays();

  /// Opens the system screen to grant "Display over other apps".
  Future<void> openOverlaySettings();

  /// Hands the repeating SOS alert to the native service so it keeps
  /// vibrating even if the app process is killed mid-SOS. Returns whether the
  /// native alert actually engaged (true only when the shake detector service
  /// is running); when false, the caller should drive the alert itself.
  Future<bool> startSosAlert();

  /// Stops the native SOS alert loop, if one is running. Idempotent.
  Future<void> stopSosAlert();
}

/// Platform-channel implementation bound in [core/providers.dart].
class ShakeSosServiceChannel implements ShakeSosService {
  const ShakeSosServiceChannel();

  static const MethodChannel _channel = MethodChannel('guardianher/shake_sos');

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<void> openBatteryOptimizationSettings() =>
      _channel.invokeMethod<void>('openBatteryOptimizationSettings');

  @override
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
      false;

  @override
  Future<String?> manufacturerToken() =>
      _channel.invokeMethod<String?>('manufacturerToken');

  @override
  Future<bool> canDrawOverlays() async =>
      await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;

  @override
  Future<void> openOverlaySettings() =>
      _channel.invokeMethod<void>('openOverlaySettings');

  @override
  Future<bool> startSosAlert() async =>
      await _channel.invokeMethod<bool>('startSosAlert') ?? false;

  @override
  Future<void> stopSosAlert() =>
      _channel.invokeMethod<void>('stopSosAlert');
}