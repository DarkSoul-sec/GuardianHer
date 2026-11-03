import 'package:record/record.dart';

import '../domain/voice_recorder.dart';

/// [VoiceRecorder] backed by the `record` package (AAC-LC in `.m4a`).
///
/// Capture is deficit-free by construction: [stop] ends the session and the
/// controller persists only what the engine confirms. Never throws — engine
/// failures become `false`/`null` so the controller can fail honestly.
class RecordPackageVoiceRecorder implements VoiceRecorder {
  RecordPackageVoiceRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  bool _disposed = false;

  @override
  Future<bool> start(String outputPath) async {
    if (_disposed) return false;
    try {
      if (await _recorder.isRecording()) return false;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
        ),
        path: outputPath,
      );
      return await _recorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Duration?> stop() async {
    // The engine reports no duration; the controller's own elapsed ticker is
    // authoritative. Non-null means "a file was finalized".
    try {
      final path = await _recorder.stop();
      return path == null ? null : Duration.zero;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancel();
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
