/// Normalization and validation rules for trusted-contact phone numbers.
///
/// Numbers are stored in a single canonical form: the sequence of digits
/// (E.164 country code + national number). A leading `+` and all formatting
/// characters (spaces, dashes, dots, parentheses) are removed so that
/// `+91XXXXXXXXXX`, `91XXXXXXXXXX` and `+91 XXX XXX XXXX` all normalize to the
/// same value and cannot be stored as separate contacts.
abstract final class PhoneNumber {
  PhoneNumber._();

  /// Inclusive minimum digit count (shortest national numbers).
  static const int minDigits = 7;

  /// Inclusive maximum digit count (ITU E.164 limit).
  static const int maxDigits = 15;

  /// Whether [value] represents a valid phone number.
  static bool isValid(String value) {
    final digits = normalize(value);
    return digits.length >= minDigits && digits.length <= maxDigits;
  }

  /// Returns the canonical, digits-only representation of [value].
  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final code in value.trim().codeUnits) {
      if (code >= 0x30 && code <= 0x39) {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }
}
