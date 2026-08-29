/// Indian vehicle-registration normalization (Phase D). Pure functions.
///
/// RULES:
/// - Storage/comparison uses the CANONICAL compact form ("DL01AB1234");
///   display derives a spaced rendering ("DL 01 AB 1234") from it.
/// - Separators (spaces, hyphens, dots, underscores) and case are
///   presentation noise: they are stripped/uppercased for every input.
/// - Well-known Indian shapes are recognized so display can be pretty.
/// - Anything else that is plausibly a plate (foreign or unusual manual
///   format) passes through UNCHANGED apart from case/separator cleanup —
///   we never force foreign plates into an Indian shape.
library;

/// Matches the classic RTO shape: state code + 1-2 digit series +
/// 1-3 letter series + exactly 4 digits. e.g. DL01AB1234, MH12AB1234,
/// KA05MK4532.
final RegExp _classicIndian = RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{1,3})(\d{4})$');

/// BH-series shape introduced for transferable registrations:
/// YYBH####XX, e.g. 22BH1234AB.
final RegExp _bhSeries = RegExp(r'^(\d{2})BH(\d{4})([A-Z]{2})$');

/// Characters allowed in a plausible plate after cleanup. Deliberately
/// generous: IATA-style foreign plates and custom formats must survive.
final RegExp _plausiblePlate = RegExp(r'^[A-Z0-9]{4,12}$');

/// Outcome of [normalizeRegistration].
sealed class RegistrationResult {
  const RegistrationResult();
}

final class RegistrationValid extends RegistrationResult {
  const RegistrationValid(this.canonical);

  /// Compact canonical form, safe to store and compare.
  final String canonical;
}

final class RegistrationInvalid extends RegistrationResult {
  const RegistrationInvalid(this.reasonKey);

  /// Stable key for UI copy; never contains the user's input.
  final String reasonKey;
}

/// Normalizes raw user input into the canonical registration form.
///
/// Never logs; never throws on odd input — junk returns [RegistrationInvalid]
/// with a stable reason key ('empty' | 'tooLong' | 'invalidCharacters').
RegistrationResult normalizeRegistration(String? raw) {
  final cleaned = (raw ?? '')
      .trim()
      .replaceAll(RegExp(r'[\s\-._]'), '')
      .toUpperCase();
  if (cleaned.isEmpty) {
    return const RegistrationInvalid('empty');
  }
  if (cleaned.length > 12) {
    return const RegistrationInvalid('tooLong');
  }
  // Indian shapes first (pure recognition — no rewriting).
  if (_classicIndian.hasMatch(cleaned) || _bhSeries.hasMatch(cleaned)) {
    return RegistrationValid(cleaned);
  }
  // Everything else: accept as manual/foreign format without reshaping.
  if (_plausiblePlate.hasMatch(cleaned)) {
    return RegistrationValid(cleaned);
  }
  return const RegistrationInvalid('invalidCharacters');
}

/// Renders a canonical registration for humans: spaced Indian layout when
/// the value matches a known Indian shape, otherwise unchanged.
String formatRegistration(String canonical) {
  final classic = _classicIndian.firstMatch(canonical);
  if (classic != null) {
    final state = classic.group(1)!;
    final series = classic.group(2)!;
    final letters = classic.group(3)!;
    final number = classic.group(4)!;
    return '$state $series $letters $number';
  }
  final bh = _bhSeries.firstMatch(canonical);
  if (bh != null) {
    return '${bh.group(1)} BH ${bh.group(2)} ${bh.group(3)}';
  }
  return canonical;
}
