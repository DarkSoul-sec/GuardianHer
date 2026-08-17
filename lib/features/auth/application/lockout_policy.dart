/// Escalating lockout schedule for repeated incorrect PIN attempts.
///
/// The delay grows with the number of failures and is always finite: the user
/// is never permanently locked out.
abstract final class LockoutPolicy {
  LockoutPolicy._();

  /// Attempts allowed without any lockout.
  static const int freeAttempts = 4;

  /// Returns the lockout delay applied after [attemptCount] failures.
  static Duration delayForAttempt(int attemptCount) {
    if (attemptCount <= freeAttempts) return Duration.zero;
    return switch (attemptCount) {
      5 => const Duration(seconds: 30),
      6 => const Duration(minutes: 1),
      7 => const Duration(minutes: 5),
      _ => const Duration(minutes: 15),
    };
  }
}