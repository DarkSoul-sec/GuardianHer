/// Centralized error model shared across all features.
///
/// Operations return [Result]s carrying a [Failure] instead of throwing
/// platform exceptions across layer boundaries. Concrete subclasses (in other
/// libraries) describe the failure category so UI code can map them to
/// user-facing messages without leaking platform-specific exceptions into
/// widgets.
abstract class Failure {
  const Failure({required this.message, this.code});

  final String message;
  final String? code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// An unexpected, category-agnostic failure.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([String message = 'An unexpected error occurred.'])
      : super(message: message, code: 'unexpected');
}

/// A failure reported by a platform/device integration (e.g. plugin error).
final class PlatformFailure extends Failure {
  const PlatformFailure([String message = 'A platform error occurred.'])
      : super(message: message, code: 'platform');
}

/// A failure reading or writing persistent storage.
final class StorageFailure extends Failure {
  const StorageFailure([String message = 'A storage error occurred.'])
      : super(message: message, code: 'storage');
}

/// A failure caused by a denied OS permission.
final class PermissionDeniedFailure extends Failure {
  const PermissionDeniedFailure([String message = 'Permission was denied.'])
      : super(message: message, code: 'permission_denied');
}

/// No phone app on the device can handle the dialer intent.
final class NoDialerAvailableFailure extends Failure {
  const NoDialerAvailableFailure([
    String message = 'Unable to open the dialer. No phone app was found.',
  ]) : super(message: message, code: 'no_dialer');
}

/// No messaging app on the device can handle the SMS intent.
final class NoSmsAppAvailableFailure extends Failure {
  const NoSmsAppAvailableFailure([
    String message = 'Unable to open messaging. No SMS app was found.',
  ]) : super(message: message, code: 'no_sms_app');
}

/// WhatsApp could not be opened for a chat (app missing, unresolvable
/// deep link, platform error). This says nothing about whether the recipient
/// is registered on WhatsApp — that can never be known from this side.
final class NoWhatsAppAppAvailableFailure extends Failure {
  const NoWhatsAppAppAvailableFailure([
    String message = 'Unable to open WhatsApp. The app may not be installed.',
  ]) : super(message: message, code: 'no_whatsapp_app');
}

/// A phone number cannot be turned into a valid WhatsApp chat target.
final class InvalidWhatsAppNumberFailure extends Failure {
  const InvalidWhatsAppNumberFailure([
    String message = "This contact's number cannot be used with WhatsApp.",
  ]) : super(message: message, code: 'invalid_whatsapp_number');
}

/// No email application on the device can handle the mailto intent.
final class NoEmailAppAvailableFailure extends Failure {
  const NoEmailAppAvailableFailure([
    String message = 'Unable to open email. No email app was found.',
  ]) : super(message: message, code: 'no_email_app');
}

/// The system share sheet could not be opened.
final class ShareUnavailableFailure extends Failure {
  const ShareUnavailableFailure([
    String message = 'Unable to open sharing options.',
  ]) : super(message: message, code: 'share_unavailable');
}

/// No map application or browser could open the location.
final class UnableToOpenMapsFailure extends Failure {
  const UnableToOpenMapsFailure([
    String message = 'Unable to open maps.',
  ]) : super(message: message, code: 'unable_to_open_maps');
}

/// The user denied (or never granted) notification permission.
final class NotificationPermissionDeniedFailure extends Failure {
  const NotificationPermissionDeniedFailure([
    String message = 'Notifications unavailable.',
  ]) : super(message: message, code: 'notifications_unavailable');
}

/// The device has no vibrator or the vibration call failed.
final class VibrationUnavailableFailure extends Failure {
  const VibrationUnavailableFailure([
    String message = 'Vibration is not available on this device.',
  ]) : super(message: message, code: 'vibration_unavailable');
}

/// An intent-based platform operation (dialer/SMS/notification) failed.
final class PlatformActionFailure extends Failure {
  const PlatformActionFailure([
    String message = 'Unable to open this action right now.',
  ]) : super(message: message, code: 'platform_action');
}