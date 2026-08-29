import '../../../core/error/failures.dart';

/// Base type for the safety-session feature failures.
sealed class SafetySessionFailure extends Failure {
  const SafetySessionFailure({
    super.message = 'A safety session error occurred.',
    super.code,
  });
}

/// A transition the session machine does not allow from the current state.
///
/// Carries the current and requested status names so callers can decide
/// whether to surface the problem or treat the request as a no-op — the same
/// shape the SOS state machine uses.
final class InvalidSafetyTransitionFailure extends SafetySessionFailure {
  const InvalidSafetyTransitionFailure({
    required this.currentStatus,
    required this.requestedStatus,
    super.message = 'This action is not available right now.',
    super.code = 'invalid_safety_transition',
  });

  final String currentStatus;
  final String requestedStatus;
}

/// A start was requested while another safety session is already running.
///
/// Product rule: at most ONE active safety session may exist. A journey that
/// escalates to SOS does not create a second session — it transforms the
/// existing one (handled by the application layer, not by re-starting).
final class DuplicateActiveSessionFailure extends SafetySessionFailure {
  const DuplicateActiveSessionFailure({
    required this.runningType,
    super.message = 'A safety session is already running.',
    super.code = 'duplicate_active_session',
  });

  /// The storage name of the session type that is already running.
  final String runningType;
}
