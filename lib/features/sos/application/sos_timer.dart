import 'dart:async';

/// Abstraction over a countdown timer so the SOS controller stays testable.
///
/// Implementations tick once per second and must call [onTick] synchronously
/// on [start] with the initial remaining seconds so the controller can render
/// the countdown immediately.
abstract interface class SosTimer {
  /// Whether a countdown is currently running.
  bool get isRunning;

  /// Starts a countdown of [duration] seconds.
  ///
  /// [onTick] receives the remaining whole seconds after each elapsed second;
  /// [onComplete] fires once, when the countdown reaches zero. Starting a new
  /// countdown stops any previous one.
  void start({
    required Duration duration,
    required void Function(int remainingSeconds) onTick,
    required void Function() onComplete,
  });

  /// Stops the countdown and discards its callbacks.
  void stop();
}

/// [SosTimer] backed by `dart:async` [Timer.periodic].
///
/// Ticks every second; the initial [onTick] call happens synchronously from
/// [start] so the very first frame already shows the full remaining time.
class TimerSosTimer implements SosTimer {
  static const Duration _tick = Duration(seconds: 1);

  Timer? _timer;
  int _remaining = 0;
  void Function()? _onComplete;

  @override
  bool get isRunning => _timer?.isActive ?? false;

  @override
  void start({
    required Duration duration,
    required void Function(int remainingSeconds) onTick,
    required void Function() onComplete,
  }) {
    stop();
    _onComplete = onComplete;
    _remaining = (duration.inMilliseconds / 1000).ceil();
    if (_remaining <= 0) {
      _onComplete = null;
      onComplete();
      return;
    }

    onTick(_remaining);
    _timer = Timer.periodic(_tick, (timer) {
      _remaining -= 1;
      if (_remaining <= 0) {
        timer.cancel();
        _timer = null;
        final complete = _onComplete;
        _onComplete = null;
        complete?.call();
      } else {
        onTick(_remaining);
      }
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _onComplete = null;
  }
}
