/// Lifecycle states of a [SafetySession].
///
/// Explicit transitions only — see [SafetySessionMachine]. Terminal states
/// (`completed`, `failed`, `expired`) accept a new `start`; nothing else does.
enum SafetySessionStatus {
  /// No session exists.
  idle,

  /// A start request was accepted; the owning feature is still bringing the
  /// session up (permissions, service, capture).
  starting,

  /// The session is fully running.
  active,

  /// An end was requested; teardown (stop tracking, stop services) is running.
  stopping,

  /// Ended normally (by the user or by the feature's own completion).
  completed,

  /// Could not start, or teardown failed hard. Terminal.
  failed,

  /// Its time-to-live elapsed. Terminal.
  expired;

  bool get isTerminal => switch (this) {
        SafetySessionStatus.completed ||
        SafetySessionStatus.failed ||
        SafetySessionStatus.expired =>
          true,
        _ => false,
      };

  bool get isActiveLike =>
      this == SafetySessionStatus.active || this == SafetySessionStatus.starting;
}
