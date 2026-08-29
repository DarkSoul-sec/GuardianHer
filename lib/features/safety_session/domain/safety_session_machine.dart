import '../../../core/result/result.dart';
import 'safety_session.dart';
import 'safety_session_failures.dart';
import 'safety_session_id.dart';
import 'safety_session_status.dart';
import 'safety_session_type.dart';

/// Pure, platform-independent state machine for a safety session.
///
/// Mirrors the SOS state machine's contract: deterministic, immutable, no
/// timers/clocks/storage/UI. The application layer drives it and decides how
/// to surface rejections.
///
/// Allowed transitions:
/// * `start`    — none (idle) or terminal → `starting`
/// * `activate` — `starting` → `active`
/// * `stop`     — `active` → `stopping`
/// * `complete` — `stopping` → `completed`
/// * `expire`   — `active`/`starting` → `expired`
/// * `fail`     — `starting`/`active`/`stopping` → `failed`
///
/// A start while another session is running (starting/active/stopping) fails
/// with [DuplicateActiveSessionFailure]: there is at most ONE active safety
/// session; a journey escalates to SOS by transforming the session, never by
/// opening a second one.
abstract final class SafetySessionMachine {
  static Result<SafetySession> start(
    SafetySession? current, {
    required SafetySessionType type,
    required SafetySessionId id,
    required DateTime now,
    List<String> recipientContactIds = const [],
  }) {
    if (current != null && !current.isTerminal) {
      return Err(
        DuplicateActiveSessionFailure(runningType: current.type.storageName),
      );
    }
    return Ok(
      SafetySession.start(
        id: id,
        type: type,
        startedAt: now,
        recipientContactIds: recipientContactIds,
      ),
    );
  }

  static Result<SafetySession> activate(
    SafetySession current, {
    required DateTime now,
  }) {
    if (current.status != SafetySessionStatus.starting) {
      return Err(_invalid(current, SafetySessionStatus.active));
    }
    return Ok(
      current.copyWith(
        status: SafetySessionStatus.active,
        activatedAt: now,
      ),
    );
  }

  static Result<SafetySession> stop(
    SafetySession current, {
    required DateTime now,
  }) {
    if (current.status != SafetySessionStatus.active) {
      return Err(_invalid(current, SafetySessionStatus.stopping));
    }
    return Ok(current.copyWith(status: SafetySessionStatus.stopping));
  }

  static Result<SafetySession> complete(
    SafetySession current, {
    required DateTime now,
  }) {
    if (current.status != SafetySessionStatus.stopping) {
      return Err(_invalid(current, SafetySessionStatus.completed));
    }
    return Ok(
      current.copyWith(
        status: SafetySessionStatus.completed,
        endedAt: now,
      ),
    );
  }

  static Result<SafetySession> expire(
    SafetySession current, {
    required DateTime now,
  }) {
    const target = SafetySessionStatus.expired;
    if (!current.isActiveLike) {
      return Err(_invalid(current, target));
    }
    return Ok(current.copyWith(status: target, endedAt: now));
  }

  static Result<SafetySession> fail(
    SafetySession current, {
    required DateTime now,
  }) {
    const target = SafetySessionStatus.failed;
    switch (current.status) {
      case SafetySessionStatus.starting:
      case SafetySessionStatus.active:
      case SafetySessionStatus.stopping:
        return Ok(current.copyWith(status: target, endedAt: now));
      default:
        return Err(_invalid(current, target));
    }
  }

  static InvalidSafetyTransitionFailure _invalid(
    SafetySession current,
    SafetySessionStatus requested,
  ) {
    return InvalidSafetyTransitionFailure(
      currentStatus: current.status.name,
      requestedStatus: requested.name,
    );
  }
}
