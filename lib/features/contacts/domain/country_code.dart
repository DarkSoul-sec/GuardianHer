/// A dialing-country prefix offered in the contact form.
class CountryCode {
  const CountryCode(this.iso, this.dialing);

  /// ISO 3166-1 alpha-2 country code.
  final String iso;

  /// International dialing prefix including the leading `+`, e.g. `+91`.
  final String dialing;

  /// Default prefix: India (`+91`), matching the primary audience.
  static const CountryCode india = CountryCode('IN', '+91');

  static const String defaultDialing = '+91';

  /// Commonly used dialing codes shown in the selector.
  static const List<CountryCode> common = [
    india,
    CountryCode('US', '+1'),
    CountryCode('GB', '+44'),
    CountryCode('AU', '+61'),
    CountryCode('AE', '+971'),
    CountryCode('SA', '+966'),
    CountryCode('PK', '+92'),
    CountryCode('BD', '+880'),
    CountryCode('SG', '+65'),
    CountryCode('NP', '+977'),
  ];
}