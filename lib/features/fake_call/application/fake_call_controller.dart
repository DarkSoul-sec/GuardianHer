import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fake_call_alert.dart';
import '../domain/fake_call_config.dart';
import '../domain/fake_call_state.dart';
import 'fake_call_providers.dart';

/// Drives the simulated incoming-call lifecycle.
///
/// All alerting is local: a Dart [Timer] moves scheduled → ringing, the
/// native alert seam loops the system ringtone (+vibration when enabled), and
/// a heads-up notification covers the backgrounded case (tap reopens the
/// incoming screen). Nothing here dials, sends SMS, uses GPS/microphone, or
/// touches the network. Failures in alert/notification seams never break the
/// state machine — they are caught and ignored.
///
/// Single-flight: scheduling while busy is absorbed silently (same rule as
/// journey duplicate starts). All timers are cancelled on every transition
/// and on dispose so no timer outlives the controller.
class FakeCallController extends Notifier<FakeCallState> {
  /// How long an unanswered ringing call lasts before timing out.
  static const ringTimeout = Duration(seconds: 30);

  Timer? _fireTimer;
  Timer? _ringTimeoutTimer;
  Timer? _tickTimer;

  DateTime Function() get _clock => ref.read(fakeCallClockProvider);
  FakeCallAlertService get _alert => ref.read(fakeCallAlertServiceProvider);
  FakeCallNotifier get _notifier => ref.read(fakeCallNotifierProvider);

  @override
  FakeCallState build() {
    ref.onDispose(_cancelAllTimers);
    return const FakeCallIdle();
  }

  /// Schedules a fake call with [config]. Absorbed silently while busy.
  Future<void> scheduleFakeCall(FakeCallConfig config) async {
    if (state.isBusy) return;
    _cancelAllTimers();
    final fireAt = _clock().add(config.delay.duration);
    state = FakeCallScheduled(config: config, fireAt: fireAt);
    try {
      await _notifier.scheduleIncomingCall(
        callerName: config.callerName,
        fireAt: fireAt,
      );
    } catch (_) {
      // Notification is a best-effort fallback; the Dart timer is primary.
    }
    final delay = fireAt.difference(_clock());
    _fireTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _fireTimer = null;
      showIncomingCall();
    });
  }

  /// Moves scheduled → ringing and starts ringtone/vibration. Idempotent:
  /// only acts from the scheduled state.
  Future<void> showIncomingCall() async {
    final current = state;
    if (current is! FakeCallScheduled) return;
    _cancelAllTimers();
    state = FakeCallRinging(config: current.config, rangAt: _clock());
    try {
      await _alert.startAlert(vibrate: current.config.vibrationEnabled);
    } catch (_) {
      // Alert failure must never break the state machine.
    }
    try {
      await _notifier.showIncomingCallNow(callerName: current.config.callerName);
    } catch (_) {
      // Best-effort fallback only.
    }
    _ringTimeoutTimer = Timer(ringTimeout, () {
      _ringTimeoutTimer = null;
      _finishRinging(FakeCallEndReason.timedOut);
    });
  }

  /// Answers the ringing call: stops the alert, starts the per-second timer.
  /// Only acts from the ringing state.
  Future<void> answerCall() async {
    final current = state;
    if (current is! FakeCallRinging) return;
    _cancelAllTimers();
    await _silence();
    state = FakeCallActive(config: current.config, answeredAt: _clock());
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = state;
      if (now is FakeCallActive) {
        state = now.tick();
      } else {
        _tickTimer?.cancel();
        _tickTimer = null;
      }
    });
  }

  /// Declines the ringing call. Only acts from the ringing state.
  Future<void> declineCall() async {
    if (state is! FakeCallRinging) return;
    _cancelAllTimers();
    await _silence();
    state = FakeCallEnded(reason: FakeCallEndReason.declined, endedAt: _clock());
  }

  /// Ends the answered call. Only acts from the active state.
  Future<void> endCall() async {
    if (state is! FakeCallActive) return;
    _cancelAllTimers();
    await _silence();
    state = FakeCallEnded(reason: FakeCallEndReason.hungUp, endedAt: _clock());
  }

  /// Cancels a scheduled call before it rings. Absorbed otherwise.
  Future<void> cancelFakeCall() async {
    final current = state;
    if (current is! FakeCallScheduled) return;
    _cancelAllTimers();
    await _silence();
    state = FakeCallEnded(reason: FakeCallEndReason.cancelled, endedAt: _clock());
  }

  /// Returns to idle (clears the terminal banner).
  void dismiss() {
    if (state is! FakeCallEnded && state is! FakeCallIdle) return;
    _cancelAllTimers();
    state = const FakeCallIdle();
  }

  Future<void> _finishRinging(FakeCallEndReason reason) async {
    _cancelAllTimers();
    await _silence();
    state = FakeCallEnded(reason: reason, endedAt: _clock());
  }

  /// Stops ringtone/vibration and removes the notification. Never throws.
  Future<void> _silence() async {
    try {
      await _alert.stopAlert();
    } catch (_) {}
    try {
      await _notifier.cancelIncomingCall();
    } catch (_) {}
  }

  void _cancelAllTimers() {
    _fireTimer?.cancel();
    _fireTimer = null;
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }
}
