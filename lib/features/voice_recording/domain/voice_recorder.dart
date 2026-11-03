import 'dart:async';

/// Seam over the audio capture engine (`record` package).
///
/// Implementations must never throw: every method catches platform errors and
/// reports them through return values so the controller can fail honestly.
abstract interface class VoiceRecorder {
  /// Starts capturing to [outputPath]. Returns false when capture cannot start.
  Future<bool> start(String outputPath);

  /// Stops capture and returns the recorded duration, or null on failure.
  /// Deletes nothing; the file stays at [outputPath] for the repository.
  Future<Duration?> stop();

  /// Aborts capture and deletes any partial file. Idempotent.
  Future<void> cancel();

  /// Releases native resources. Idempotent.
  Future<void> dispose();
}
