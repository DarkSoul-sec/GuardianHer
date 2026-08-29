import 'package:url_launcher/url_launcher.dart';

import '../core/error/failures.dart';
import '../core/platform/email_service.dart';
import '../core/result/result.dart';

/// Builds the `mailto:` URI for an email addressed to every [addresses].
///
/// Addresses are joined with `,` (the RFC 6068 convention) and percent-encoded
/// by [Uri]; [subject] and [body] ride the query parameters.
Uri buildMailtoUri(
  List<String> addresses,
  String subject,
  String body,
) {
  return Uri(
    scheme: 'mailto',
    path: addresses.join(','),
    queryParameters: {'subject': subject, 'body': body},
  );
}

/// Opens the system email composer pre-filled with recipients and message.
///
/// Uses `ACTION_SENDTO` (via `mailto:`), which requires no permissions and
/// never sends anything silently — the user reviews and sends. This service
/// only ever reports "composer opened"; it cannot and does not claim the
/// email was sent.
class UrlLauncherEmailService implements EmailService {
  const UrlLauncherEmailService();

  @override
  Future<Result<void>> compose({
    required List<String> addresses,
    required String subject,
    required String body,
  }) async {
    final uri = buildMailtoUri(addresses, subject, body);
    try {
      if (!await canLaunchUrl(uri)) {
        return const Err(NoEmailAppAvailableFailure());
      }
      final launched = await launchUrl(uri);
      if (!launched) {
        return const Err(NoEmailAppAvailableFailure());
      }
      return const Ok(null);
    } catch (_) {
      return const Err(PlatformActionFailure('Unable to open email.'));
    }
  }
}
