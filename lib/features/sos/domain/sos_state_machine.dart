import '../../../core/result/result.dart';
import 'sos_event.dart';
import 'sos_failures.dart';
import 'sos_status.dart';

/// Pure, platform-independent state machine for an SOS session.
///
/// All transitions are deterministic and produce a new immutable [SosEvent];
/// nothing here touches timers, clocks, storage, or the UI. The application
/// layer is responsible for driving the machine (feeding it timestamps and
/// the current event) and for rejecting or ignoring invalid requests.
///
/// Allowed transitions:
/// * [start]      — `idle`/`completed` → `countdown`
/// * [activate]   — `countdown` → `active`
/// * [cancel]     — `countdown`/`active` → `cancelling`
/// * [complete]   — `active` → `completed`; `cancelling` → `completed`
/// * [resetToIdle] — `completed` → `idle`
///
/// [cancel] and [complete] are idempotent in the terminal-ish states they
/// drive towards: cancelling stays cancelling, completed stays completed.
abstract final class SosStateMachine {
  /// Begins a new session with a pre-activation [countdownDuration].
  ///
  /// Only allowed when there is no current session or the last one is
  /// [SosStatus.completed].
  static Result<SosEvent> start(
    SosEvent? current, {
    required SosEventId id,
    required DateTime now,
    required Duration countdownDuration,
  }) {
    if (current != null &&
        current.status != SosStatus.completed &&
        current.status != SosStatus.idle) {
      return Err(
        InvalidTransitionFailure(
          currentStatus: current.status.name,
          requestedStatus: SosStatus.countdown.name,
        ),
      );
    }
    return Ok(
      SosEvent(
        id: id,
        startedAt: now,
        status: SosStatus.countdown,
        countdownDuration: countdownDuration,
      ),
    );
  }

  /// Activates the session after the countdown, if still armed.
  static Result<SosEvent> activate(SosEvent event, {required DateTime now}) {
    if (event.status != SosStatus.countdown) {
      return Err(
        InvalidTransitionFailure(
          currentStatus: event.status.name,
          requestedStatus: SosStatus.active.name,
        ),
      );
    }
    return Ok(event.copyWith(status: SosStatus.active, activatedAt: now));
  }

  /// Requests cancellation of an armed or active session.
  ///
  /// Idempotent: a session already [SosStatus.cancelling] stays cancelling.
  static Result<SosEvent> cancel(SosEvent event, {required DateTime now}) {
    switch (event.status) {
      case SosStatus.countdown:
      case SosStatus.active:
        return Ok(
          event.copyWith(
            status: SosStatus.cancelling,
            reason: SosTerminationReason.cancelled,
          ),
        );
      case SosStatus.cancelling:
        return Ok(event);
      case SosStatus.idle:
      case SosStatus.completed:
        return Err(
          InvalidTransitionFailure(
            currentStatus: event.status.name,
            requestedStatus: SosStatus.cancelling.name,
          ),
        );
    }
  }

  /// Finalizes the session.
  ///
  /// From [SosStatus.active] the session completes normally. From
  /// [SosStatus.cancelling] the earlier cancellation reason is preserved.
  /// Idempotent in [SosStatus.completed].
  static Result<SosEvent> complete(SosEvent event, {required DateTime now}) {
    switch (event.status) {
      case SosStatus.active:
        return Ok(
          event.copyWith(
            status: SosStatus.completed,
            completedAt: now,
            reason: SosTerminationReason.completed,
          ),
        );
      case SosStatus.cancelling:
        return Ok(
          event.copyWith(status: SosStatus.completed, completedAt: now),
        );
      case SosStatus.completed:
        return Ok(event);
      case SosStatus.idle:
      case SosStatus.countdown:
        return Err(
          InvalidTransitionFailure(
            currentStatus: event.status.name,
            requestedStatus: SosStatus.completed.name,
          ),
        );
    }
  }

  /// Returns the session to [SosStatus.idle] after it completed.
  static Result<SosEvent> resetToIdle(SosEvent event) {
    if (event.status != SosStatus.completed) {
      return Err(
        InvalidTransitionFailure(
          currentStatus: event.status.name,
          requestedStatus: SosStatus.idle.name,
        ),
      );
    }
    return Ok(
      SosEvent(
        id: event.id,
        startedAt: event.startedAt,
        status: SosStatus.idle,
        countdownDuration: event.countdownDuration,
        activatedAt: event.activatedAt,
        completedAt: event.completedAt,
        reason: event.reason,
      ),
    );
  }
}
