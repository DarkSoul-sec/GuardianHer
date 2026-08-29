import 'package:url_launcher/url_launcher.dart';

import '../core/error/failures.dart';
import '../core/platform/sms_service.dart';
import '../core/result/result.dart';

/// Builds the `sms:` URI that opens the system messaging app with
/// [normalizedNumber] (digits only) and [body] pre-filled.
///
/// When [normalizedNumber] is empty (e.g. sharing a location with an
/// unspecified recipient), the URI carries only the body and the user picks
/// the recipient in the messaging app.
Uri buildSmsUri(String normalizedNumber, String body) {
  if (normalizedNumber.isEmpty) {
    return Uri(
      scheme: 'sms',
      queryParameters: {'body': body},
    );
  }
  return Uri(
    scheme: 'sms',
    path: '+$normalizedNumber',
    queryParameters: {'body': body},
  );
}

/// Opens the system SMS composer pre-filled with a recipient and message.
///
/// Uses `ACTION_SENDTO` (via `sms:`) which requires no `SEND_SMS` permission
/// and never sends anything silently — the user reviews and sends. This service
/// only ever reports "composer opened"; it cannot and does not claim the
/// message was sent.
class UrlLauncherSmsService implements SmsService {
  const UrlLauncherSmsService();

  @override
  Future<Result<void>> openComposer({
    required String phoneNumber,
    String? body,
  }) async {
    final uri = buildSmsUri(phoneNumber, body ?? '');
    try {
      if (!await canLaunchUrl(uri)) {
        return Err(NoSmsAppAvailableFailure());
      }
      final launched = await launchUrl(uri);
      if (!launched) {
        return Err(NoSmsAppAvailableFailure());
      }
      return const Ok(null);
    } catch (_) {
      return Err(PlatformActionFailure('Unable to open messaging.'));
    }
  }
}