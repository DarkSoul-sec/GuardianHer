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

  /// Combines a dialing prefix (e.g. `+91`) with the user-entered number.
  ///
  /// A value the user already typed with a leading `+` is treated as complete
  /// and normalized as-is; otherwise the prefix digits are prepended, so a
  /// user can simply type `8965421745` with the `+91` prefix applied.
  static String withDialingCode(String dialingCode, String value) {
    if (value.trim().startsWith('+')) {
      return normalize(value);
    }
    return normalize(dialingCode) + normalize(value);
  }

  /// Strips a leading [dialingCode] (e.g. `+91`) from a stored digits-only
  /// [stored] number, for display in edit forms. Returns [stored] unchanged
  /// when it does not carry that prefix.
  static String stripDialingCode(String dialingCode, String stored) {
    final code = normalize(dialingCode);
    if (code.isEmpty || stored.length <= code.length) {
      return stored;
    }
    return stored.startsWith(code) ? stored.substring(code.length) : stored;
  }

  /// Canonical digits-only number for WhatsApp deep links (`wa.me/<digits>`).
  ///
  /// WhatsApp requires the full international number WITHOUT any formatting:
  /// no `+`, no spaces, dashes or parentheses, and no trunk-prefix `0`. This
  /// is a presentation-target rule layered on top of the storage form — it
  /// never changes what is stored.
  ///
  /// Rules, applied to the normalized digits of [value]:
  ///
  /// * already carrying the default dialing code (`91…`) → returned as-is;
  /// * starting with a trunk `0` → the zeros are stripped before the dialing
  ///   code is prepended (`09876543210` → `919876543210`);
  /// * short enough to be a national number (≤ 11 digits) → the dialing code
  ///   is prepended (`9876543210` → `919876543210`);
  /// * anything longer that does not start with `91` is assumed to already
  ///   carry a different country code and is returned unchanged, so a stored
  ///   `447911123456` is NOT corrupted into a pseudo-Indian number.
  static String toWhatsAppDigits(String value, {String dialingCode = '+91'}) {
    var digits = normalize(value);
    final code = normalize(dialingCode);
    if (digits.startsWith(code)) {
      return digits;
    }
    if (digits.startsWith('0')) {
      digits = digits.replaceFirst(RegExp('^0+'), '');
    }
    if (digits.length <= 11 && code.isNotEmpty && !digits.startsWith(code)) {
      return code + digits;
    }
    return digits;
  }
}
