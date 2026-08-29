import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/failures.dart';
import '../../../core/platform/email_service.dart';
import '../../../core/platform/share_service.dart';
import '../../../core/result/result.dart';
import '../../../data/email_service_impl.dart';
import '../../../data/share_service_impl.dart';
import '../domain/check_in_failures.dart';
import '../domain/check_in_message.dart';
import '../domain/check_in_message_sender.dart';

/// Builds the `sms:` URI for a check-in addressed to every [numbers].
///
/// Recipients are joined with `,` (comma) — the separator accepted by both
/// Google Messages and Samsung Messages for pre-filled multi-recipient drafts
/// (`;` is Android-convention but iOS/Exchange-flavored apps reject it, and
/// some dialers treat it as a literal). Every number is prefixed with `+` so
/// apps parse the stored international digits (e.g. `919876543210`) as a full
/// E.164 address instead of a local number missing its country code.
Uri buildCheckInSmsUri(List<String> numbers, String body) {
  if (numbers.isEmpty) {
    return Uri(scheme: 'sms', queryParameters: {'body': body});
  }
  return Uri(
    scheme: 'sms',
    path: [for (final number in numbers) '+$number'].join(','),
    queryParameters: {'body': body},
  );
}

/// User-confirmed check-in delivery with channel fallback (Phase 3G).
///
/// Tries, in order:
/// 1. **SMS composer** — `ACTION_SENDTO sms:` with recipients + body
///    pre-filled. The user reviews and taps send; nothing is sent silently.
/// 2. **Email composer** — when no SMS app resolves (common on tablets and
///    Wi-Fi-only devices), opens a `mailto:` draft to every contact that has
///    an optional email address stored.
/// 3. **System share sheet** — last resort: hands the message text to any
///    installed app (WhatsApp, Telegram, copy-to-clipboard, …).
///
/// Only when all three channels fail does this return a failure, and each
/// step's outcome is surfaced through distinct failure types so the UI can
/// tell the user exactly what happened. Like SOS messaging, the wording stays
/// honest: the composer was *opened*, never "sent".
class CascadeCheckInMessageSender implements CheckInMessageSender {
  const CascadeCheckInMessageSender({
    this.email = const UrlLauncherEmailService(),
    this.share = const SharePlusShareService(),
    Future<Result<void>> Function(Uri uri)? openSms,
  }) : _openSms = openSms ?? _launchSmsComposer;

  final EmailService email;
  final ShareService share;

  /// SMS channel launch step. Injectable so tests can simulate "no SMS app"
  /// or success without touching the platform channel.
  final Future<Result<void>> Function(Uri uri) _openSms;

  /// Opens the SMS composer via `ACTION_SENDTO` (multi-recipient URI).
  ///
  /// Mirrors the SOS SMS service semantics: no permission, nothing sent
  /// silently, and a distinct failure when no messaging app resolves.
  static Future<Result<void>> _launchSmsComposer(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) {
        return const Err(NoSmsAppAvailableFailure());
      }
      final launched = await launchUrl(uri);
      if (!launched) {
        return const Err(NoSmsAppAvailableFailure());
      }
      return const Ok(null);
    } catch (_) {
      return const Err(PlatformActionFailure('Unable to open messaging.'));
    }
  }

  @override
  Future<Result<void>> send(CheckInMessage message) async {
    // Channel 1: SMS composer.
    switch (await _openSms(
      buildCheckInSmsUri(message.recipientPhoneNumbers, message.body),
    )) {
      case Ok():
        return const Ok(null);
      case Err(:final failure) when failure is! NoSmsAppAvailableFailure:
        return Err(CheckInSenderFailure(failure.message));
      case Err():
        break; // No SMS app on this device — try email.
    }

    // Channel 2: email fallback (only useful if at least one contact has an
    // address on file).
    if (message.recipientEmails.isNotEmpty) {
      switch (await email.compose(
        addresses: message.recipientEmails,
        subject: 'Safety check-in',
        body: message.body,
      )) {
        case Ok():
          return const Ok(null);
        case Err(:final failure) when failure is! NoEmailAppAvailableFailure:
          return Err(CheckInSenderFailure(failure.message));
        case Err():
          break; // No email app either — fall through to share.
      }
    }

    // Channel 3: system share sheet as the universal fallback.
    switch (await share.shareText(message.body)) {
      case Ok():
        return const Ok(null);
      case Err(:final failure):
        return Err(CheckInSenderFailure(
          'No messaging or share option is available. '
          '${failure.message}',
        ));
    }
  }
}
