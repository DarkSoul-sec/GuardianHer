import '../result/result.dart';

/// Abstraction over the device vibrator for the SOS alert.
///
/// The SOS pattern must be bounded: [playSosAlert] emits a single, short
/// non-repeating pattern that stops on its own. Implementations also expose an
/// explicit [stop] for cancellation cleanup and must be idempotent.
abstract interface class VibrationService {
  /// Whether the device reports a vibrator.
  Future<bool> hasVibrator();

  /// Plays the one-shot SOS alert pattern (three short bursts).
  ///
  /// Returns a failure when the device has no vibrator or the platform call
  /// fails. Never repeats or loops.
  Future<Result<void>> playSosAlert();

  /// Stops any in-flight vibration. Idempotent; safe to call at any time.
  Future<Result<void>> stop();
}
