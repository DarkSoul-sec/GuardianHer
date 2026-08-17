/// Validation rules for stored PIN credentials.
///
/// Enforces that decoded credential material uses an accepted PBKDF2 iteration
/// count and the expected salt/hash lengths. Iteration counts below the floor
/// are too weak to accept; counts above the ceiling would let a crafted stored
/// credential stall the app for an unbounded time, so both ends are bounded.
class CredentialPolicy {
  const CredentialPolicy({
    this.minIterations = defaultIterations,
    this.maxIterations = 10000000,
    this.saltLength = 16,
    this.hashLength = 32,
  });

  /// Default PBKDF2 iteration count for newly created credentials (OWASP 2023
  /// recommendation for PBKDF2-HMAC-SHA256).
  static const int defaultIterations = 600000;

  /// Minimum PBKDF2 iteration count for accepted credentials. Matches
  /// [defaultIterations] so credentials created by this app always decode.
  final int minIterations;

  /// Maximum accepted iteration count, guarding against CPU-exhaustion via a
  /// crafted stored credential.
  final int maxIterations;

  /// Expected salt length in bytes (128-bit).
  final int saltLength;

  /// Expected derived key length in bytes (256-bit).
  final int hashLength;

  /// Whether a stored credential with [iterations], [saltLength] and
  /// [hashLength] satisfies this policy. Format version and algorithm id are
  /// validated by the caller against the format constants.
  bool isValid({
    required int iterations,
    required int saltLength,
    required int hashLength,
  }) {
    if (iterations < minIterations || iterations > maxIterations) return false;
    if (saltLength != this.saltLength) return false;
    if (hashLength != this.hashLength) return false;
    return true;
  }
}