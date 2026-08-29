/// Abstraction over direct SMS sending via the native Android SmsManager.
///
/// Unlike [SmsService] which opens the system SMS composer for user review,
/// this service sends SMS messages silently through the platform API. It
/// requires the `SEND_SMS` runtime permission and a SIM card with SMS
/// capability.
///
/// Intended for emergency use only (Guardian HER SOS workflow). Personal /
/// sideloaded distribution — not subject to Play Store default-SMS-app
/// restrictions.
abstract interface class DirectSmsService {
  /// Whether the device has a SIM card ready for SMS.
  Future<bool> checkSimReady();

  /// Whether the `SEND_SMS` permission is currently granted.
  Future<bool> hasPermission();

  /// Requests the `SEND_SMS` permission and returns whether it was granted.
  Future<bool> requestPermission();

  /// Sends an SMS to [phoneNumber] with [body].
  ///
  /// Returns a record with `success` and an optional `error` description.
  /// A failure does not throw — callers inspect the result.
  Future<({bool success, String? error})> sendSms({
    required String phoneNumber,
    required String body,
  });

  /// Current battery charge percentage (0–100), or `null` when unavailable.
  Future<int?> getBatteryPercentage();
}
