import 'dart:async';

import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Playback state for one saved voice note at a time.
sealed class VoicePlaybackState {
  const VoicePlaybackState();

  /// Id of the loaded track, or null when nothing is loaded.
  String? get trackId => switch (this) {
        VoicePlaybackStopped() => null,
        VoicePlaybackPlaying(:final trackId) => trackId,
        VoicePlaybackPaused(:final trackId) => trackId,
      };
}

final class VoicePlaybackStopped extends VoicePlaybackState {
  const VoicePlaybackStopped();
}

final class VoicePlaybackPlaying extends VoicePlaybackState {
  const VoicePlaybackPlaying({
    required this.trackId,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final String trackId;
  final Duration position;
  final Duration duration;
}

final class VoicePlaybackPaused extends VoicePlaybackState {
  const VoicePlaybackPaused({
    required this.trackId,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final String trackId;
  final Duration position;
  final Duration duration;
}

/// Plays one saved voice note at a time with just_audio.
///
/// Loading a different track stops the current one first, so two recordings
/// can never play simultaneously. All player errors resolve to stopped —
/// never crash, never leak: subscriptions are cancelled on every transition
/// and on dispose.
class VoicePlaybackController extends Notifier<VoicePlaybackState> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  String? _loadedId;

  @override
  VoicePlaybackState build() {
    ref.onDispose(() {
      unawaited(_teardown());
    });
    return const VoicePlaybackStopped();
  }

  /// Plays [path] identified by [id], stopping any current track first.
  Future<void> play({required String id, required String path}) async {
    final current = state;
    if (current is VoicePlaybackPaused && current.trackId == id) {
      await resume();
      return;
    }
    await _teardown();
    final player = AudioPlayer();
    _player = player;
    _loadedId = id;
    try {
      await player.setFilePath(path);
    } catch (_) {
      await _teardown();
      return;
    }
    final duration = player.duration ?? Duration.zero;
    _positionSub = player.positionStream.listen((position) {
      final now = state;
      if (now is VoicePlaybackPlaying && now.trackId == _loadedId) {
        state = VoicePlaybackPlaying(
          trackId: now.trackId,
          position: position,
          duration: player.duration ?? duration,
        );
      }
    });
    _stateSub = player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        stop();
      }
    });
    try {
      await player.play();
    } catch (_) {
      await _teardown();
      return;
    }
    state = VoicePlaybackPlaying(trackId: id, duration: duration);
  }

  /// Pauses the current track. No-op unless playing.
  Future<void> pause() async {
    final current = state;
    if (current is! VoicePlaybackPlaying) return;
    try {
      await _player?.pause();
    } catch (_) {}
    final position = _player?.position ?? current.position;
    state = VoicePlaybackPaused(
      trackId: current.trackId,
      position: position,
      duration: current.duration,
    );
  }

  /// Resumes a paused track. No-op otherwise.
  Future<void> resume() async {
    final current = state;
    if (current is! VoicePlaybackPaused) return;
    try {
      await _player?.play();
    } catch (_) {
      await _teardown();
      return;
    }
    state = VoicePlaybackPlaying(
      trackId: current.trackId,
      position: current.position,
      duration: current.duration,
    );
  }

  /// Seeks within the current track. No-op when nothing is loaded.
  Future<void> seek(Duration position) async {
    if (state.trackId == null) return;
    try {
      await _player?.seek(position);
    } catch (_) {}
  }

  /// Stops playback and releases the player.
  Future<void> stop() async {
    await _teardown();
    if (state is! VoicePlaybackStopped) {
      state = const VoicePlaybackStopped();
    }
  }

  Future<void> _teardown() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _loadedId = null;
  }
}
