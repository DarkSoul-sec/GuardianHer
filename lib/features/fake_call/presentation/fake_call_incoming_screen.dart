import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_theme.dart';
import '../application/fake_call_providers.dart';
import '../domain/fake_call_state.dart';

/// Simulated incoming-call experience (no telephony).
///
/// Ringing: avatar, caller name, "Incoming call", Decline/Answer.
/// Answered: caller name, per-second timer, "Simulated call" label, End.
/// Everything is local; the timer is the only thing running.
class FakeCallIncomingScreen extends ConsumerWidget {
  const FakeCallIncomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fakeCallControllerProvider);
    return switch (state) {
      FakeCallRinging(:final config) => _RingingView(
          callerName: config.callerName,
          callerNumber: config.callerNumber,
          onDecline: () =>
              ref.read(fakeCallControllerProvider.notifier).declineCall(),
          onAnswer: () =>
              ref.read(fakeCallControllerProvider.notifier).answerCall(),
        ),
      FakeCallActive(:final config, :final elapsed) => _ActiveView(
          callerName: config.callerName,
          elapsed: elapsed,
          onEnd: () =>
              ref.read(fakeCallControllerProvider.notifier).endCall(),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _RingingView extends StatelessWidget {
  const _RingingView({
    required this.callerName,
    required this.callerNumber,
    required this.onDecline,
    required this.onAnswer,
  });

  final String callerName;
  final String callerNumber;
  final VoidCallback onDecline;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.guardianIndigo,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              Text(
                'Simulated incoming call',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              _Avatar(name: callerName, size: 120),
              const SizedBox(height: 24),
              Text(
                callerName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                callerNumber,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Simulated call',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    key: const Key('fake-call-decline'),
                    icon: Icons.call_end,
                    label: 'Decline',
                    background: const Color(0xFFFF5A5A),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onDecline();
                    },
                  ),
                  _CallButton(
                    key: const Key('fake-call-answer'),
                    icon: Icons.call,
                    label: 'Answer',
                    background: AppTheme.successGreen,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onAnswer();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveView extends StatelessWidget {
  const _ActiveView({
    required this.callerName,
    required this.elapsed,
    required this.onEnd,
  });

  final String callerName;
  final Duration elapsed;
  final VoidCallback onEnd;

  static String formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.guardianIndigo,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              Text(
                'Simulated call',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              _Avatar(name: callerName, size: 96),
              const SizedBox(height: 20),
              Text(
                callerName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatElapsed(elapsed),
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const Spacer(),
              _CallButton(
                key: const Key('fake-call-end'),
                icon: Icons.call_end,
                label: 'End Call',
                background: const Color(0xFFFF5A5A),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onEnd();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.lavenderSoft,
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: AppTheme.guardianIndigo,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, size: 32, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
