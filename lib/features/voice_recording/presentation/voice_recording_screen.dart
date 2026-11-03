import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';
import '../application/voice_recording_providers.dart';

/// Voice Recordings: recorder entry + local history.
///
/// Recording is explicit, visible and stoppable; leaving the screen while
/// recording stops and saves (never records in the background).
class VoiceRecordingScreen extends ConsumerStatefulWidget {
  const VoiceRecordingScreen({super.key});

  @override
  ConsumerState<VoiceRecordingScreen> createState() =>
      _VoiceRecordingScreenState();
}

class _VoiceRecordingScreenState extends ConsumerState<VoiceRecordingScreen>
    with WidgetsBindingObserver {
  bool _rationaleShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ref.read(voiceRecordingControllerProvider.notifier).handleAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceRecordingControllerProvider);
    // Stop detail-screen playback when returning here with nothing playing
    // is handled by the detail screen itself on dispose.

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'Voice Recording',
          style: GoogleFonts.inter(
            color: AppTheme.guardianIndigo,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Record an audio note when you need to document an incident.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textBody,
              ),
            ),
            const SizedBox(height: 20),
            _RecorderCard(
              state: state,
              onStart: () => _onStartPressed(context),
              onStop: () => ref
                  .read(voiceRecordingControllerProvider.notifier)
                  .stopAndSave(),
              onDiscard: () => ref
                  .read(voiceRecordingControllerProvider.notifier)
                  .discardRecording(),
              onOpenSettings: () => ref
                  .read(voiceRecordingControllerProvider.notifier)
                  .openSettings(),
              onDismissError: () => ref
                  .read(voiceRecordingControllerProvider.notifier)
                  .dismissBanner(),
            ),
            const SizedBox(height: 24),
            const GhSectionTitle(title: 'Voice Recordings'),
            _RecordingList(
              recordings: state.recordings,
              onOpen: (id) => context.push(
                '${AppRoutes.voiceRecording}/detail',
                extra: id,
              ),
              onShare: (id) => _share(context, id),
              onDelete: (id) => _confirmDelete(context, id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onStartPressed(BuildContext context) async {
    if (_rationaleShown) {
      await ref.read(voiceRecordingControllerProvider.notifier).startRecording();
      return;
    }
    _rationaleShown = true;
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Microphone access'),
        content: const Text(
          'GuardianHer needs microphone access to record an audio note '
          'that you choose to create. Recording only happens while this '
          'screen is visible, and only after you press Start Recording.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed == true && context.mounted) {
      await ref.read(voiceRecordingControllerProvider.notifier).startRecording();
    }
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

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: const Text(
          'The audio file and its details will be permanently removed '
          'from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('voice-delete-confirm'),
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
          .deleteRecording(id);
    }
  }
}

class _RecorderCard extends StatelessWidget {
  const _RecorderCard({
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.onDiscard,
    required this.onOpenSettings,
    required this.onDismissError,
  });

  final VoiceRecordingState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDiscard;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final recording =
        state is VoiceRecordingActive ? state as VoiceRecordingActive : null;
    final error = state is VoiceError ? state as VoiceError : null;
    final saved = state is VoiceSaved ? state as VoiceSaved : null;
    return GhCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          if (recording != null) ...[
            _RecDot(elapsedSeconds: recording.elapsed.inSeconds),
            const SizedBox(height: 12),
            Text(
              'REC',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppTheme.sosCoral,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _format(recording.elapsed),
              style: GoogleFonts.inter(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppTheme.guardianIndigo,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Recording…',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textBody,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('voice-stop'),
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop Recording'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: AppTheme.sosCoral,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onDiscard,
              child: Text(
                'Discard',
                style: GoogleFonts.inter(color: AppTheme.textBody),
              ),
            ),
          ] else if (state is VoiceStopping) ...[
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            const Text('Saving…'),
          ] else ...[
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
              'Ready to record',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.guardianIndigo,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.sosCoral,
                ),
              ),
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              ),
            ],
            if (saved != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saved “${saved.saved.displayName}”.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.successGreenDark,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('voice-start'),
              onPressed: state is VoiceRequestingPermission ? null : onStart,
              icon: const Icon(Icons.fiber_manual_record, size: 18),
              label: const Text('Start Recording'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// Recording indicator driven by the controller's per-second ticks (no
/// ticker of its own, so widget tests settle): blinks on alternate seconds.
class _RecDot extends StatelessWidget {
  const _RecDot({required this.elapsedSeconds});

  final int elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: elapsedSeconds.isEven ? 1 : 0.35,
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.sosCoral,
        ),
      ),
    );
  }
}

class _RecordingList extends StatelessWidget {
  const _RecordingList({
    required this.recordings,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final List<VoiceRecording> recordings;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) {
      return const GhCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No recordings yet.'),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final rec in recordings)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RecordingTile(
              recording: rec,
              onOpen: () => onOpen(rec.id),
              onShare: () => onShare(rec.id),
              onDelete: () => onDelete(rec.id),
            ),
          ),
      ],
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.recording,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final VoiceRecording recording;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  static String formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GhCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.lavenderSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.mic_outlined,
              color: AppTheme.guardianIndigo,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recording.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.guardianIndigo,
                  ),
                ),
                Text(
                  '${recording.createdAt.day.toString().padLeft(2, '0')} '
                  '${_month(recording.createdAt.month)} '
                  '${recording.createdAt.year} · '
                  '${recording.createdAt.hour.toString().padLeft(2, '0')}:'
                  '${recording.createdAt.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textBody,
                  ),
                ),
                Text(
                  formatDuration(recording.duration),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppTheme.textFaint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('voice-play-${recording.id}'),
            tooltip: 'Play',
            onPressed: onOpen,
            icon: const Icon(Icons.play_arrow_rounded),
            color: AppTheme.guardianIndigo,
          ),
          IconButton(
            key: Key('voice-share-${recording.id}'),
            tooltip: 'Share',
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_outlined),
            color: AppTheme.textBody,
          ),
          IconButton(
            key: Key('voice-delete-${recording.id}'),
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: AppTheme.sosCoral,
          ),
        ],
      ),
    );
  }

  static String _month(int month) => switch (month) {
        1 => 'Jan',
        2 => 'Feb',
        3 => 'Mar',
        4 => 'Apr',
        5 => 'May',
        6 => 'Jun',
        7 => 'Jul',
        8 => 'Aug',
        9 => 'Sep',
        10 => 'Oct',
        11 => 'Nov',
        _ => 'Dec',
      };
}
