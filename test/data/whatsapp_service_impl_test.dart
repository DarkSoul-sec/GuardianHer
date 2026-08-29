import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/data/whatsapp_service_impl.dart';
import 'package:guardianher/features/contacts/domain/phone_number.dart';

void main() {
  group('PhoneNumber.toWhatsAppDigits', () {
    test('every common input form canonicalizes to the same target', () {
      const expected = '919876543210';
      const inputs = [
        '+919876543210', // stored E.164 with +
        '919876543210', // stored digits-only
        '9876543210', // bare national
        '+91 98765 43210', // spaced
        '+91-98765-43210', // dashed
        '(+91) 98765432 10', // parenthesized
        '09876543210', // trunk-prefixed national
        '0 98765 43210', // trunk prefix + spaces
      ];
      for (final input in inputs) {
        expect(
          PhoneNumber.toWhatsAppDigits(input),
          expected,
          reason: 'input "$input" must canonicalize to $expected',
        );
      }
    });

    test('a number already carrying the default code is returned unchanged',
        () {
      expect(PhoneNumber.toWhatsAppDigits('919876543210'), '919876543210');
    });

    test('a foreign country code is never overwritten with the default', () {
      // A stored UK number must not be corrupted into a pseudo-Indian one.
      expect(PhoneNumber.toWhatsAppDigits('447911123456'), '447911123456');
    });

    test('the dialing code is injectable for non-default regions', () {
      expect(
        PhoneNumber.toWhatsAppDigits('07911123456', dialingCode: '+44'),
        '447911123456',
      );
    });
  });

  group('canonicalWhatsAppDigits', () {
    test('rejects numbers outside the E.164 window', () {
      expect(canonicalWhatsAppDigits(''), isNull);
      expect(canonicalWhatsAppDigits('123'), isNull); // too short
      expect(
        canonicalWhatsAppDigits('12345678901234567890'),
        isNull,
      ); // too long
    });

    test('produces digits-only output for every valid input', () {
      final digits = canonicalWhatsAppDigits('+91 98765 43210');
      expect(digits, '919876543210');
      // The deep-link contract: no formatting characters survive.
      expect(digits!.contains('+'), isFalse);
      expect(RegExp(r'^[0-9]+$').hasMatch(digits), isTrue);
    });
  });

  group('buildWhatsAppChatUrl', () {
    test('targets the canonical international number with the body pre-filled',
        () {
      final uri = buildWhatsAppChatUrl('+91 98765 43210', body: 'hello');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'whatsapp');
      expect(uri.host, 'send');
      expect(uri.queryParameters['phone'], '919876543210');
      expect(uri.queryParameters['text'], 'hello');
    });

    test('all formatted inputs collapse onto one identical URL', () {
      final a = buildWhatsAppChatUrl('+919876543210');
      final b = buildWhatsAppChatUrl('9876543210');
      final c = buildWhatsAppChatUrl('09876543210');
      final d = buildWhatsAppChatUrl('+91-98765-43210');
      expect(a, b);
      expect(b, c);
      expect(c, d);
      expect(d!.queryParameters['phone'], '919876543210');
    });

    test('never emits a plus sign or whitespace in the phone parameter', () {
      final uri = buildWhatsAppChatUrl('+91 98765 43210');
      final phone = uri!.queryParameters['phone']!;
      expect(phone.startsWith('+'), isFalse);
      expect(phone.contains(' '), isFalse);
      expect(phone.contains('-'), isFalse);
      expect(phone.contains('('), isFalse);
      expect(phone.startsWith('0'), isFalse);
    });

    test('returns null instead of a broken link for unusable numbers', () {
      expect(buildWhatsAppChatUrl(''), isNull);
      expect(buildWhatsAppChatUrl('abc'), isNull);
      expect(buildWhatsAppChatUrl('12'), isNull);
    });
  });
}
