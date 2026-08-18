import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/contacts/domain/phone_number.dart';

void main() {
  group('PhoneNumber.isValid', () {
    test('accepts 7 to 15 digits', () {
      expect(PhoneNumber.isValid('1234567'), isTrue);
      expect(PhoneNumber.isValid('123456789012345'), isTrue);
    });

    test('rejects fewer than 7 digits', () {
      expect(PhoneNumber.isValid('123456'), isFalse);
      expect(PhoneNumber.isValid(''), isFalse);
    });

    test('rejects more than 15 digits', () {
      expect(PhoneNumber.isValid('1234567890123456'), isFalse);
    });

    test('accepts formatted international numbers', () {
      expect(PhoneNumber.isValid('+91 12345 67890'), isTrue);
      expect(PhoneNumber.isValid('+1 (555) 123-4567'), isTrue);
      expect(PhoneNumber.isValid('44 7911 123456'), isTrue);
    });

    test('rejects alphabetic and punctuation input', () {
      expect(PhoneNumber.isValid('call mom'), isFalse);
      expect(PhoneNumber.isValid('+abc'), isFalse);
    });
  });

  group('PhoneNumber.normalize', () {
    test('strips formatting and keeps digits', () {
      expect(PhoneNumber.normalize('+91 12345 67890'), '911234567890');
      expect(PhoneNumber.normalize('+1 (555) 123-4567'), '15551234567');
      expect(PhoneNumber.normalize('44 7911 123456'), '447911123456');
    });

    test('treats leading plus and no-plus forms identically', () {
      expect(PhoneNumber.normalize('+911234567890'), PhoneNumber.normalize('911234567890'));
      expect(PhoneNumber.normalize('+91 12345 67890'), PhoneNumber.normalize('+911234567890'));
    });

    test('returns empty for non-digit input', () {
      expect(PhoneNumber.normalize('+'), '');
      expect(PhoneNumber.normalize('abc'), '');
    });
  });
}