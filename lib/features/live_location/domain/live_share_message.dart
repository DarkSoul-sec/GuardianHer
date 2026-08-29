import '../../../core/error/failures.dart';

/// The ONE link the user shares. Contains the random token — nothing else:
/// no coordinates, no phone numbers, no contact names.
String buildLiveShareUrl({required String baseUrl, required String token}) =>
    '$baseUrl/live/$token';

/// Message body handed to the user-confirmed communication channels.
///
/// The URL is the live-tracking mechanism; the message NEVER claims that
/// SMS/WhatsApp itself provides live tracking, and never claims the
/// recipient's registration state anywhere.
String buildLiveShareMessage({
  required String shareUrl,
  required DateTime expiresAt,
}) {
  final expiresLocal = expiresAt.toLocal();
  final hour = expiresLocal.hour.toString().padLeft(2, '0');
  final minute = expiresLocal.minute.toString().padLeft(2, '0');
  return 'GuardianHer live location:\n'
      '$shareUrl\n\n'
      'This link expires at $hour:$minute.';
}

/// Failure → honest one-line reason for the live screen.
String liveFailureCopy(Failure failure) {
  final code = failure.code;
  if (code == 'no_whatsapp_app') return 'WhatsApp is not available.';
  if (code == 'no_sms_app') return 'Messaging is not available.';
  if (code == 'share_unavailable') return 'Sharing is not available.';
  if (code == 'not_configured') {
    return 'Live sharing is not available in this build.';
  }
  return 'This action did not work. Try another way to share.';
}
