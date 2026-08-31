import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:guardianher/core/platform/whatsapp_service.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/domain/phone_number.dart';

/// Canonical digits-only chat target for [phoneNumber], or `null` when the
/// number cannot produce a valid WhatsApp target.
String? canonicalWhatsAppDigits(String phoneNumber) {
  final digits = PhoneNumber.toWhatsAppDigits(phoneNumber);
  if (digits.length < PhoneNumber.minDigits ||
      digits.length > PhoneNumber.maxDigits) {
    return null;
  }
  return digits;
}

/// Builds the `whatsapp://send?phone=<digits>&text=<body>` app deep link.
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

/// Data source for sending emergency WhatsApp messages.
///
/// Uses WhatsApp deep links (`whatsapp://send`) to open pre-filled chats.
/// User still needs to tap "Send" in WhatsApp - true auto-send is not
/// possible on-device without WhatsApp Business API (cloud-based).
class WhatsAppDataSource {
  WhatsAppDataSource();

  /// Opens a pre-filled WhatsApp chat for [number] with [message].
  ///
  /// Returns `true` if WhatsApp chat was opened successfully,
  /// `false` if WhatsApp is not installed or number is invalid.
  Future<bool> openWhatsAppChat({
    required String number,
    required String message,
  }) async {
    final uri = buildWhatsAppChatUrl(number, body: message);
    if (uri == null) {
      return false;
    }

    try {
      if (!await canLaunchUrl(uri)) {
        return false;
      }
      final launched = await launchUrl(uri);
      return launched;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Opens WhatsApp chats for multiple contacts sequentially.
  ///
  /// Returns count of successfully opened chats.
  Future<int> openWhatsAppForAllContacts({
    required List<String> numbers,
    required String message,
  }) async {
    int successCount = 0;
    for (final number in numbers) {
      final success = await openWhatsAppChat(number: number, message: message);
      if (success) {
        successCount++;
      }
      // Small delay between launches to avoid overwhelming the system
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return successCount;
  }
}