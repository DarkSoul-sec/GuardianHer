import 'fake_call_config.dart';

/// Lifecycle of one simulated incoming call.
///
/// The controller moves idle → scheduled → ringing → active → ended.
/// There is exactly one fake call at a time; scheduling while busy is
/// absorbed (returns the current state unchanged).
sealed class FakeCallState {
  const FakeCallState();

  /// Whether a fake call occupies the feature (schedule refused while true).
  bool get isBusy => this is FakeCallScheduled || this is FakeCallRinging || this is FakeCallActive;
}

/// No fake call. Entry point for scheduling a new one.
final class FakeCallIdle extends FakeCallState {
  const FakeCallIdle({this.notice});

  /// Honest one-line explanation when the last transition did not start a
  /// call (e.g. a duplicate schedule, or a completed call's summary).
  /// Null right after boot.
  final String? notice;

  @override
  bool operator ==(Object other) =>
      other is FakeCallIdle && other.notice == notice;

  @override
  int get hashCode => notice.hashCode;
}

/// A fake call will ring at [fireAt].
final class FakeCallScheduled extends FakeCallState {
  const FakeCallScheduled({required this.config, required this.fireAt});

  final FakeCallConfig config;
  final DateTime fireAt;
}

/// The fake incoming-call screen is showing. Ringtone (native) and vibration
/// are running. Ends by answer, decline, or timeout.
final class FakeCallRinging extends FakeCallState {
  const FakeCallRinging({required this.config, required this.rangAt});

  final FakeCallConfig config;
  final DateTime rangAt;
}

/// The user "answered": a local per-second timer runs. No telephony, no
/// microphone, no audio — simulated only.
final class FakeCallActive extends FakeCallState {
  const FakeCallActive({
    required this.config,
    required this.answeredAt,
    this.elapsed = Duration.zero,
  });

  final FakeCallConfig config;
  final DateTime answeredAt;

  /// Simulated call duration, ticked once per second.
  final Duration elapsed;

  FakeCallActive tick() =>
      FakeCallActive(config: config, answeredAt: answeredAt, elapsed: elapsed + const Duration(seconds: 1));
}

/// Terminal. [reason] explains what happened; the UI shows it verbatim-ish
/// and offers to schedule another call.
final class FakeCallEnded extends FakeCallState {
  const FakeCallEnded({required this.reason, required this.endedAt});

  final FakeCallEndReason reason;
  final DateTime endedAt;
}

/// Why a fake call ended. Never silent: the reason is always shown.
enum FakeCallEndReason {
  /// The user declined the ringing call.
  declined,

  /// The user ended the answered call.
  hungUp,

  /// Nobody answered within the ring timeout.
  timedOut,

  /// A scheduled call was cancelled before ringing.
  cancelled,
}
