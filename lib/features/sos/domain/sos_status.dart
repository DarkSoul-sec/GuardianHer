/// Lifecycle status of an SOS session.
///
/// The canonical flow is:
/// `idle → countdown → active → (cancelling →) completed → idle`.
/// Only [SosStatus.completed] and [SosStatus.idle] allow starting a new session.
enum SosStatus {
  /// No SOS session is running.
  idle,

  /// A session is armed but not yet activated (pre-activation grace period).
  countdown,

  /// The emergency workflow is active.
  active,

  /// A cancellation is being finalized before the session completes.
  cancelling,

  /// The session ended; awaiting the user to dismiss and return to [idle].
  completed,
}

/// Why an SOS session ended.
///
/// A session is [cancelled] when the user aborted it (during countdown or
/// while active). It is [completed] when it ran through the emergency
/// workflow without user cancellation.
enum SosTerminationReason {
  /// The user cancelled the session.
  cancelled,

  /// The session ended normally.
  completed,
}
