import 'voice_recording.dart';

/// Explicit lifecycle of visible, user-initiated voice recording.
///
/// Pause/resume is deliberately omitted: only start → stop → saved is
/// offered so every transition is reliable on all supported devices.
sealed class VoiceRecordingState {
  const VoiceRecordingState();

  /// Recordings newest-first. Always present so the list never flashes empty.
  List<VoiceRecording> get recordings => switch (this) {
        VoiceIdle(:final recordings) => recordings,
        VoiceRequestingPermission(:final recordings) => recordings,
        VoiceRecordingActive(:final recordings) => recordings,
        VoiceStopping(:final recordings) => recordings,
        VoiceSaved(:final recordings) => recordings,
        VoiceError(:final recordings) => recordings,
      };
}

/// No recording in progress. Entry point.
final class VoiceIdle extends VoiceRecordingState {
  const VoiceIdle({this.recordings = const [], this.notice});

  @override
  final List<VoiceRecording> recordings;

  /// Honest one-line explanation (e.g. after a dismissed banner). Null normally.
  final String? notice;
}

/// Checking microphone permission; never records in this state.
final class VoiceRequestingPermission extends VoiceRecordingState {
  const VoiceRequestingPermission({this.recordings = const []});

  @override
  final List<VoiceRecording> recordings;
}

/// The microphone is active and visible. [elapsed] ticks once per second.
final class VoiceRecordingActive extends VoiceRecordingState {
  const VoiceRecordingActive({
    this.recordings = const [],
    required this.startedAt,
    this.elapsed = Duration.zero,
  });

  @override
  final List<VoiceRecording> recordings;
  final DateTime startedAt;
  final Duration elapsed;

  VoiceRecordingActive tick() => VoiceRecordingActive(
        recordings: recordings,
        startedAt: startedAt,
        elapsed: elapsed + const Duration(seconds: 1),
      );
}

/// Wrapping up the recorder; transient.
final class VoiceStopping extends VoiceRecordingState {
  const VoiceStopping({this.recordings = const []});

  @override
  final List<VoiceRecording> recordings;
}

/// A recording was just saved; the UI highlights it.
final class VoiceSaved extends VoiceRecordingState {
  const VoiceSaved({this.recordings = const [], required this.saved});

  @override
  final List<VoiceRecording> recordings;
  final VoiceRecording saved;
}

/// Something failed without crashing. Recording never starts from here.
final class VoiceError extends VoiceRecordingState {
  const VoiceError({this.recordings = const [], required this.message});

  @override
  final List<VoiceRecording> recordings;
  final String message;
}
