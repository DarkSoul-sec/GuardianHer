import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../data/voice_recording_repository.dart';
import '../domain/voice_recorder.dart';
import '../domain/voice_recording.dart';
import '../domain/voice_recording_state.dart';
import 'voice_recording_providers.dart';

/// Owns the visible voice-note lifecycle.
///
/// The microphone is touched only inside [startRecording] after an explicit
/// user tap confirmed permission, and only ever while the recording screen
/// is visible: [handleAppPaused] stops and saves when the app loses the
/// foreground. All timers are cancelled on every transition and on dispose
/// so nothing leaks and nothing records in the background.
class VoiceRecordingController extends Notifier<VoiceRecordingState> {
  Timer? _tickTimer;
  String? _activePath;
  bool _saving = false;

  DateTime Function() get _clock => ref.read(voiceRecordingClockProvider);
  PermissionService get _permissions => ref.read(permissionServiceProvider);
  VoiceRecorder get _recorder => ref.read(voiceRecorderProvider);
  VoiceRecordingRepository get _repository =>
      ref.read(voiceRecordingRepositoryProvider);

  @override
  VoiceRecordingState build() {
    ref.onDispose(() {
      _tickTimer?.cancel();
      _tickTimer = null;
      // Never leave the microphone running past the controller's life.
      // Guarded: the container may already be torn down here.
      try {
        unawaited(_recorder.cancel());
      } catch (_) {}
    });
    // State must not be read or written during build; load after mount.
    Future(() => _loadFresh());
    return const VoiceIdle();
  }

  /// Initial load that never touches `state` (unsafe during build).
  Future<void> _loadFresh() async {
    try {
      final result = await _repository.loadAll();
      final recordings = result.fold((list) => list, (_) => const <VoiceRecording>[]);
      final current = state;
      if (current is VoiceRecordingActive || current is VoiceStopping) return;
      if (current is VoiceSaved || current is VoiceError) return;
      state = VoiceIdle(recordings: recordings);
    } catch (_) {}
  }

  /// Reloads the recording list from storage.
  Future<void> refresh() => _load();

  /// Starts a new recording after confirming microphone permission.
  ///
  /// Shows an in-app rationale first — that belongs to the presentation
  /// layer; this method only starts when permission is actually granted and
  /// never starts merely because permission exists.
  Future<void> startRecording() async {
    final current = state;
    if (current is VoiceRecordingActive ||
        current is VoiceStopping ||
        current is VoiceRequestingPermission) {
      return;
    }
    state = VoiceRequestingPermission(recordings: current.recordings);
    var status = await _permissions.status(AppPermission.microphone);
    if (status != PermissionStatus.granted) {
      status = await _permissions.request(AppPermission.microphone);
    }
    if (status != PermissionStatus.granted) {
      final denied = status == PermissionStatus.permanentlyDenied;
      state = VoiceError(
        recordings: current.recordings,
        message: denied
            ? 'Microphone access is turned off. Open Settings to enable it for voice notes.'
            : 'Microphone permission is required to record audio.',
      );
      return;
    }
    final target =
        await _repository.nextRecordingTarget(now: _clock());
    final started = await _recorder.start(target.path);
    if (!started) {
      state = VoiceError(
        recordings: current.recordings,
        message: 'Recording could not be started. Try again.',
      );
      return;
    }
    _activePath = target.path;
    state = VoiceRecordingActive(
      recordings: current.recordings,
      startedAt: _clock(),
    );
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = state;
      if (now is VoiceRecordingActive) {
        state = now.tick();
      } else {
        _tickTimer?.cancel();
        _tickTimer = null;
      }
    });
    // Stash the display name for save time.
    _pendingDisplayName = target.displayName;
  }

  String? _pendingDisplayName;

  /// Stops the active recording and saves it. Only acts while recording.
  Future<void> stopAndSave() async {
    final current = state;
    if (current is! VoiceRecordingActive || _saving) return;
    _saving = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    final elapsed = current.elapsed;
    state = VoiceStopping(recordings: current.recordings);
    try {
      final finalized = await _recorder.stop();
      final path = _activePath;
      _activePath = null;
      if (finalized == null || path == null) {
        state = VoiceError(
          recordings: current.recordings,
          message: 'The recording could not be saved. Try again.',
        );
        return;
      }
      final record = VoiceRecording(
        id: _newId(),
        path: path,
        createdAt: current.startedAt,
        duration: elapsed,
        displayName:
            _pendingDisplayName ?? 'Recording - ${_clock().toIso8601String()}',
      );
      final saved = await _repository.save(record);
      switch (saved) {
        case Ok(:final value):
          final loaded = await _repository.loadAll();
          state = VoiceSaved(
            recordings: loaded.fold((list) => list, (_) => current.recordings),
            saved: value,
          );
        case Err():
          state = VoiceError(
            recordings: current.recordings,
            message: 'The recording could not be saved. Try again.',
          );
      }
    } finally {
      _saving = false;
      _pendingDisplayName = null;
    }
  }

  /// Discards the active recording without saving. Only acts while recording.
  Future<void> discardRecording() async {
    if (state is! VoiceRecordingActive) return;
    _tickTimer?.cancel();
    _tickTimer = null;
    _activePath = null;
    _pendingDisplayName = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    await _load();
  }

  /// Stops and saves when the app leaves the foreground mid-recording.
  ///
  /// Visible-foreground recording only: GuardianHer never records secretly,
  /// so backgrounding ends the session as a saved note instead of
  /// continuing silently.
  Future<void> handleAppPaused() async {
    if (state is VoiceRecordingActive) {
      await stopAndSave();
    }
  }

  /// Deletes a recording's file and metadata.
  Future<Result<void>> deleteRecording(String id) async {
    final result = await _repository.delete(id);
    await _load(keepNotice: true);
    return result;
  }

  /// Renames a recording's display name.
  Future<Result<VoiceRecording>> renameRecording(
    String id,
    String displayName,
  ) async {
    final result =
        await _repository.rename(id: id, displayName: displayName);
    await _load(keepNotice: true);
    return result;
  }

  /// Opens the system share sheet with the audio file. The user chooses the
  /// destination; nothing is ever sent automatically.
  Future<Result<void>> shareRecording(String id) async {
    final found = await _find(id);
    if (found == null) {
      return const Err(StorageFailure('The recording was not found.'));
    }
    return ref.read(shareServiceProvider).shareFile(found.path);
  }

  /// Opens the system settings screen (permission recovery path).
  Future<void> openSettings() => _permissions.openSettings();

  /// Returns to the idle list, clearing banners.
  void dismissBanner() {
    final current = state;
    if (current is VoiceSaved || current is VoiceError) {
      state = VoiceIdle(recordings: current.recordings);
    } else if (current is VoiceIdle && current.notice != null) {
      state = VoiceIdle(recordings: current.recordings);
    }
  }

  Future<VoiceRecording?> _find(String id) async {
    final loaded = await _repository.loadAll();
    return loaded.fold(
      (list) {
        for (final r in list) {
          if (r.id == id) return r;
        }
        return null;
      },
      (_) => null,
    );
  }

  Future<void> _load({bool keepNotice = false}) async {
    final previous = state;
    final result = await _repository.loadAll();
    final recordings = result.fold((list) => list, (_) => previous.recordings);
    // Never clobber an in-flight recording session with a reload.
    if (state is VoiceRecording || state is VoiceStopping) return;
    if (keepNotice && previous is VoiceIdle && previous.notice != null) {
      state = VoiceIdle(recordings: recordings, notice: previous.notice);
      return;
    }
    if (state is VoiceSaved || state is VoiceError) return;
    state = VoiceIdle(recordings: recordings);
  }

  String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16);
}
