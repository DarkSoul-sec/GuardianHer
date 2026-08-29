import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../domain/sos_event.dart';
import '../domain/sos_state_machine.dart';
import 'sos_providers.dart';
import 'sos_state.dart';
import 'sos_timer.dart';

/// Drives the SOS session lifecycle on top of the pure [SosStateMachine].
///
/// The controller owns the current [SosEvent], keeps the countdown timer in
/// sync with the state, and exposes a minimal action surface used by widgets:
/// [startSos], [cancelSos], [completeSos] and [resetSos]. All timestamps come
/// from the injected clock and ids from the injected generator, so behavior is
/// fully deterministic in tests.
///
/// Cancelling an armed or active session runs through the [SosCancelling]
/// state (per the phase spec diagram) and finalizes to [SosCompleted] after a
/// short, fixed delay so the UI can acknowledge the stop before it disappears.
class SosController extends Notifier<SosState> {
  /// How long the [SosCancelling] state stays visible before completing.
  static const Duration cancellationDelay = Duration(seconds: 1);

  SosTimer get _timer => ref.read(sosTimerProvider);
  DateTime Function() get _clock => ref.read(sosClockProvider);
  Duration get _countdownDuration => ref.read(sosCountdownDurationProvider);
  SosEventId Function() get _newId => ref.read(sosEventIdGeneratorProvider);

  SosEvent? _event;

  @override
  SosState build() {
    ref.onDispose(_timer.stop);
    return const SosIdle();
  }

  /// Arms a new session: the countdown begins immediately.
  void startSos() {
    final started = SosStateMachine.start(
      _event,
      id: _newId(),
      now: _clock(),
      countdownDuration: _countdownDuration,
    );
    switch (started) {
      case Ok(:final value):
        _event = value;
        _beginCountdown(value);
      case Err(:final failure):
        debugPrint('[SOS] startSos rejected: $failure');
    }
  }

  /// Cancels an armed or active session, then finalizes it after a short delay.
  void cancelSos() {
    final event = _event;
    if (event == null) {
      return;
    }
    final result = SosStateMachine.cancel(event, now: _clock());
    switch (result) {
      case Ok(:final value):
        _event = value;
        state = SosCancelling(event: value);
        _timer.start(
          duration: cancellationDelay,
          onTick: (_) {},
          onComplete: () => _finish(),
        );
      case Err(:final failure):
        debugPrint('[SOS] cancelSos rejected: $failure');
    }
  }

  /// Ends an active session without a cancellation (future workflow use).
  void completeSos() {
    final event = _event;
    if (event == null) {
      return;
    }
    final result = SosStateMachine.complete(event, now: _clock());
    switch (result) {
      case Ok(:final value):
        _event = value;
        state = SosCompleted(event: value);
      case Err(:final failure):
        debugPrint('[SOS] completeSos rejected: $failure');
    }
  }

  /// Returns to [SosIdle] after a completed session.
  void resetSos() {
    final event = _event;
    if (event == null) {
      return;
    }
    final result = SosStateMachine.resetToIdle(event);
    switch (result) {
      case Ok(:final value):
        _event = value;
        state = const SosIdle();
      case Err(:final failure):
        debugPrint('[SOS] resetSos rejected: $failure');
    }
  }

  void _beginCountdown(SosEvent event) {
    _timer.start(
      duration: event.countdownDuration,
      onTick: (remaining) {
        final current = _event;
        if (current == null) {
          return;
        }
        state = SosCountdown(event: current, remainingSeconds: remaining);
      },
      onComplete: () {
        final current = _event;
        if (current == null) {
          return;
        }
        _activate(current);
      },
    );
  }

  void _activate(SosEvent event) {
    final result = SosStateMachine.activate(event, now: _clock());
    switch (result) {
      case Ok(:final value):
        _event = value;
        state = SosActive(event: value);
      case Err(:final failure):
        debugPrint('[SOS] activate rejected: $failure');
    }
  }

  void _finish() {
    final event = _event;
    if (event == null) {
      return;
    }
    final result = SosStateMachine.complete(event, now: _clock());
    switch (result) {
      case Ok(:final value):
        _event = value;
        state = SosCompleted(event: value);
      case Err(:final failure):
        debugPrint('[SOS] finish rejected: $failure');
    }
  }
}
