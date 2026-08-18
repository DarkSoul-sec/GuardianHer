/// Maximum number of trusted contacts for the MVP.
abstract final class TrustedContactsLimits {
  TrustedContactsLimits._();

  /// Hard upper bound on stored contacts.
  static const int max = 5;

  /// User-facing message shown when [max] is reached.
  static const String maxReachedMessage =
      'You can add up to $max trusted contacts.';
}
