import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_voice_recorder.dart';
import '../data/voice_recording_repository.dart';
import '../data/voice_recording_repository_impl.dart';
import '../domain/voice_recorder.dart';
import '../domain/voice_recording_state.dart';
import 'voice_playback_controller.dart';
import 'voice_recording_controller.dart';

export '../domain/voice_recording.dart';
export '../domain/voice_recording_state.dart';
export 'voice_playback_controller.dart';
export 'voice_recording_controller.dart';

/// Injected clock for recording timestamps (replace in tests).
final voiceRecordingClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Audio capture engine seam.
final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => RecordPackageVoiceRecorder(),
);

/// Private-storage recording repository.
final voiceRecordingRepositoryProvider =
    Provider<VoiceRecordingRepository>(
  (ref) => FileVoiceRecordingRepository(),
);

/// The voice-note lifecycle controller.
final voiceRecordingControllerProvider =
    NotifierProvider<VoiceRecordingController, VoiceRecordingState>(
  VoiceRecordingController.new,
);

/// Single-track audio playback controller.
final voicePlaybackControllerProvider =
    NotifierProvider<VoicePlaybackController, VoicePlaybackState>(
  VoicePlaybackController.new,
);
