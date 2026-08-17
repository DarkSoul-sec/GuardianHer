import '../result/result.dart';

/// Abstraction over device biometric authentication.
///
/// Backed by local_auth. Kept behind an interface so presentation and
/// application code never touch the biometric platform channel directly and
/// can be tested with fakes.
abstract interface class BiometricService {
  /// Whether the device supports and currently has biometrics enrolled.
  ///
  /// Returns `false` (never throws) when the platform cannot be queried.
  Future<bool> isAvailable();

  /// Prompts the user for biometric authentication.
  ///
  /// Returns `Ok(true)` on success. `Ok(false)` means the user canceled or
  /// biometrics could not be satisfied (the caller should fall back to PIN).
  /// Returns `Err` only for unexpected errors.
  Future<Result<bool>> authenticate({required String reason});
}