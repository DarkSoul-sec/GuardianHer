import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';
import '../application/voice_recording_providers.dart';
import '../domain/voice_recording.dart';

/// Detail screen for one saved voice note: playback with play/pause/seek,
/// position readout, rename, share and delete.
///
/// Playback stops when leaving the screen; only one track ever plays.
class RecordingDetailScreen extends ConsumerStatefulWidget {
  const RecordingDetailScreen({super.key, required this.recordingId});

  final String recordingId;

  @override
  ConsumerState<RecordingDetailScreen> createState() =>
      _RecordingDetailScreenState();
}

class _RecordingDetailScreenState
    extends ConsumerState<RecordingDetailScreen> {
  late final VoicePlaybackController _player;

  @override
  void initState() {
    super.initState();
    // Captured here: `ref` must not be used in dispose().
    _player = ref.read(voicePlaybackControllerProvider.notifier);
  }

  @override
  void dispose() {
    // Never leave audio playing behind this screen.
    _player.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordings =
        ref.watch(voiceRecordingControllerProvider).recordings;
    VoiceRecording? recording;
    for (final r in recordings) {
      if (r.id == widget.recordingId) recording = r;
    }
    if (recording == null) {
      return Scaffold(
        backgroundColor: AppTheme.appBackground,
        appBar: AppBar(title: const Text('Recording')),
        body: const Center(child: Text('This recording no longer exists.')),
      );
    }
    final rec = recording;
    final playback = ref.watch(voicePlaybackControllerProvider);
    final player = ref.read(voicePlaybackControllerProvider.notifier);

    final isCurrent = playback.trackId == rec.id;
    final isPlaying = isCurrent && playback is VoicePlaybackPlaying;
    final position = switch (playback) {
      VoicePlaybackPlaying(:final position) when isCurrent => position,
      VoicePlaybackPaused(:final position) when isCurrent => position,
      _ => Duration.zero,
    };
    final duration = switch (playback) {
      VoicePlaybackPlaying(:final duration) when isCurrent => duration,
      VoicePlaybackPaused(:final duration) when isCurrent => duration,
      _ => rec.duration,
    };

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'Recording',
          style: GoogleFonts.inter(
            color: AppTheme.guardianIndigo,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            key: const Key('voice-detail-share'),
            tooltip: 'Share',
            onPressed: () => _share(context, rec.id),
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            key: const Key('voice-detail-delete'),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, rec),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GhCard(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.lavenderSoft,
                    ),
                    child: const Icon(
                      Icons.mic_outlined,
                      size: 34,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    rec.displayName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _TransportButton(
                        key: const Key('voice-seek-back'),
                        icon: Icons.replay_10_rounded,
                        onTap: isCurrent
                            ? () => player.seek(
                                  position - const Duration(seconds: 10),
                                )
                            : null,
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          if (isPlaying) {
                            player.pause();
                          } else {
                            player.play(id: rec.id, path: rec.path);
                          }
                        },
                        child: Container(
                          key: const Key('voice-play-pause'),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.guardianIndigo,
                            boxShadow: AppTheme.softShadow(opacity: 0.2),
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      _TransportButton(
                        key: const Key('voice-seek-forward'),
                        icon: Icons.forward_10_rounded,
                        onTap: isCurrent
                            ? () => player.seek(
                                  position + const Duration(seconds: 10),
                                )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Slider(
                    value: position.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble(),
                    max: (duration.inMilliseconds <= 0
                            ? 1
                            : duration.inMilliseconds)
                        .toDouble(),
                    activeColor: AppTheme.guardianIndigo,
                    onChanged: isCurrent
                        ? (v) => player
                            .seek(Duration(milliseconds: v.round()))
                        : null,
                  ),
                  Text(
                    '${_format(position)} / ${_format(duration)}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppTheme.textBody,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('voice-rename'),
              onPressed: () => _rename(context, rec),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text('Rename'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _share(BuildContext context, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(voiceRecordingControllerProvider.notifier)
        .shareRecording(id);
    result.fold(
      (_) {},
      (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  Future<void> _confirmDelete(BuildContext context, VoiceRecording rec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: Text(
          '“${rec.displayName}” will be permanently removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.sosCoral,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(voiceRecordingControllerProvider.notifier)
          .deleteRecording(rec.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _rename(BuildContext context, VoiceRecording rec) async {
    final controller = TextEditingController(text: rec.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && context.mounted) {
      final result = await ref
          .read(voiceRecordingControllerProvider.notifier)
          .renameRecording(rec.id, name);
      if (!result.isOk && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.fold(
              (_) => '',
              (failure) => failure.message,
            )),
          ),
        );
      }
    }
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.lavenderSoft,
          ),
          child: Icon(icon, color: AppTheme.guardianIndigo),
        ),
      ),
    );
  }
}
