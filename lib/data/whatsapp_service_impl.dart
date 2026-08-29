import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/error/failures.dart';
import '../core/platform/whatsapp_service.dart';
import '../core/result/result.dart';
import '../features/contacts/domain/phone_number.dart';

/// Canonical digits-only chat target for [phoneNumber], or `null` when the
/// number cannot produce a valid WhatsApp target (no digits, or outside the
/// E.164 length bounds after canonicalization).
///
/// The value is guaranteed safe for a deep-link `phone` parameter: bare
/// international digits, no `+`, no spaces/dashes/parentheses, no trunk `0`
/// (e.g. `09876543210`, `9876543210`, `+91 98765 43210` all become
/// `919876543210`). Numbers long enough to already carry another country code
/// pass through unchanged.
String? canonicalWhatsAppDigits(String phoneNumber) {
  final digits = PhoneNumber.toWhatsAppDigits(phoneNumber);
  if (digits.length < PhoneNumber.minDigits ||
      digits.length > PhoneNumber.maxDigits) {
    return null;
  }
  return digits;
}

/// Builds the `whatsapp://send?phone=<digits>&text=<body>` app deep link.
///
/// The `whatsapp://` scheme (not `https://wa.me`) is deliberate: only the
/// WhatsApp app declares it, so an unresolvable link means "WhatsApp is not
/// usable here" and surfaces as a typed failure instead of silently opening a
/// browser tab at wa.me. Returns `null` for an invalid number.
Uri? buildWhatsAppChatUrl(String phoneNumber, {String? body}) {
  final digits = canonicalWhatsAppDigits(phoneNumber);
  if (digits == null) {
    return null;
  }
  return Uri(
    scheme: 'whatsapp',
    host: 'send',
    queryParameters: body == null || body.isEmpty
        ? {'phone': digits}
        : {'phone': digits, 'text': body},
  );
}

/// Opens a pre-filled WhatsApp chat via the `whatsapp://send` deep link.
///
/// User-confirmed by design: the chat opens with the message pre-filled and
/// the user reviews and sends it. The result only reports whether the chat
/// could be OPENED — registration state of the recipient is unknowable here
/// and is never claimed. One call performs exactly one launch attempt; retry
/// loops over multiple contacts are explicitly not implemented.
class UrlLauncherWhatsAppService implements WhatsAppService {
  const UrlLauncherWhatsAppService();

  @override
  Future<Result<void>> openChat({
    required String phoneNumber,
    String? body,
  }) async {
    final uri = buildWhatsAppChatUrl(phoneNumber, body: body);
    if (uri == null) {
      return const Err(InvalidWhatsAppNumberFailure());
    }
    try {
      if (!await canLaunchUrl(uri)) {
        return const Err(NoWhatsAppAppAvailableFailure());
      }
      final launched = await launchUrl(uri);
      if (!launched) {
        return const Err(NoWhatsAppAppAvailableFailure());
      }
      return const Ok(null);
    } on PlatformException {
      return const Err(NoWhatsAppAppAvailableFailure());
    } catch (_) {
      return const Err(PlatformActionFailure('Unable to open WhatsApp.'));
    }
  }
}
