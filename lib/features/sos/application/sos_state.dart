import '../domain/sos_event.dart';

/// States of the SOS workflow, mirroring the domain [SosStateMachine] states.
///
/// The controller drives these as the countdown timer ticks and the user
/// interacts; widgets render one state and never mutate anything directly.
sealed class SosState {
  const SosState();
}

/// No SOS session is running.
final class SosIdle extends SosState {
  const SosIdle();
}

/// A session is armed; [remainingSeconds] counts down to activation.
final class SosCountdown extends SosState {
  const SosCountdown({required this.event, required this.remainingSeconds});

  final SosEvent event;
  final int remainingSeconds;
}

/// The emergency workflow is active.
final class SosActive extends SosState {
  const SosActive({required this.event});

  final SosEvent event;
}

/// A cancellation is being finalized; the UI blocks further actions.
final class SosCancelling extends SosState {
  const SosCancelling({required this.event});

  final SosEvent event;
}

/// The session ended; awaiting the user to dismiss back to [SosIdle].
final class SosCompleted extends SosState {
  const SosCompleted({required this.event});

  final SosEvent event;
}
