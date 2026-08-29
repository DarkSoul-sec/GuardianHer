import '../../../core/error/failures.dart';

/// Base type for SOS feature failures.
sealed class SosFailure extends Failure {
  const SosFailure({
    super.message = 'An SOS error occurred.',
    super.code,
  });
}

/// A transition that is not allowed from the current state.
///
/// Carries the current and requested status so callers can decide whether to
/// surface the problem or treat the request as a no-op.
final class InvalidTransitionFailure extends SosFailure {
  const InvalidTransitionFailure({
    required this.currentStatus,
    required this.requestedStatus,
    super.message = 'This action is not available right now.',
    super.code = 'invalid_transition',
  });

  final String currentStatus;
  final String requestedStatus;
}

/// An internal SOS engine error (e.g. the countdown timer could not start).
final class SosEngineFailure extends SosFailure {
  const SosEngineFailure({
    super.message = 'The SOS engine encountered an internal error.',
    super.code = 'sos_engine',
  });
}

/// Base type for failures raised by user-triggered SOS emergency actions
/// (calling a contact, composing a message, calling emergency services).
sealed class SosActionFailure extends SosFailure {
  const SosActionFailure({
    super.message = 'This emergency action is not available.',
    super.code,
  });
}

/// The targeted phone number cannot be used for an emergency action (e.g. it
/// fails validation or the emergency number is misconfigured).
final class InvalidSosContactFailure extends SosActionFailure {
  const InvalidSosContactFailure({
    super.message = 'This contact cannot be used for an emergency action.',
    super.code = 'invalid_sos_contact',
  });
}
