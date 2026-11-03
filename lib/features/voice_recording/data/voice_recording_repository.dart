import '../../../core/result/result.dart';
import '../domain/voice_recording.dart';

/// Persistence contract for voice notes (private app storage + index).
///
/// Corrupted index entries are skipped, never crash loading. Deleting removes
/// both the audio file and its metadata so no orphans survive.
abstract interface class VoiceRecordingRepository {
  /// All recordings, newest first. Empty when nothing is stored.
  Future<Result<List<VoiceRecording>>> loadAll();

  /// Persists a finished recording's metadata; the audio file must already
  /// exist at [recording.path].
  Future<Result<VoiceRecording>> save(VoiceRecording recording);

  /// Renames a recording's display name.
  Future<Result<VoiceRecording>> rename({
    required String id,
    required String displayName,
  });

  /// Deletes the audio file and its metadata. Missing files are tolerated.
  Future<Result<void>> delete(String id);

  /// Deletes every recording file and clears the index (Delete All Data).
  Future<Result<void>> deleteAll();

  /// Builds a fresh file path + display name for a new recording.
  Future<({String path, String displayName})> nextRecordingTarget({
    required DateTime now,
  });
}
