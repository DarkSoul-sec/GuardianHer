import 'package:flutter/services.dart';

/// Holds the foreground location context for an active SOS session (Android).
///
/// Android 10+ refuses location while the screen is off, the device is locked,
/// or the app is backgrounded unless the app either holds
/// `ACCESS_BACKGROUND_LOCATION` or runs a foreground service with the
/// `location` foreground-service type. GuardianHer deliberately does NOT
/// request the background-location permission; this service is the documented
/// alternative. It is started only for the duration of an SOS session so the
/// existing one-shot capture (`LocationManagerLocationService`) can run even
/// when the SOS was triggered by a shake with the phone locked/screen-off.
///
/// The service itself does not obtain a fix — the Flutter location flow does.
/// Non-Android platforms have no channel; callers guard with the platform check
/// used across the app (`isShakeSosSupported`).
abstract interface class SosLocationService {
  /// Starts the location foreground service (idempotent).
  Future<void> start();

  /// Stops the location foreground service (idempotent).
  Future<void> stop();
}

/// Platform-channel implementation bound in `lib/core/providers.dart`.
class SosLocationServiceChannel implements SosLocationService {
  const SosLocationServiceChannel();

  static const MethodChannel _channel = MethodChannel('guardianher/sos_location');

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
