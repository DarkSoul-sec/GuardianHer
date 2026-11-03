import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/creator_links.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/guardianher_design.dart';

/// About GuardianHer — what the app is and what it does.
///
/// App-focused (unlike About Me, which is creator-focused): feature overview
/// with deep links into the real screens, plus the safety promise.
class AboutGuardianHerScreen extends ConsumerWidget {
  const AboutGuardianHerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider);

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'About GuardianHer',
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
            GhCard(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                children: [
                  const GhLogo(size: 72),
                  const SizedBox(height: 16),
                  Text(
                    'GuardianHer',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.guardianIndigo,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Personal safety, one tap away. GuardianHer helps you '
                    'alert people you trust in an emergency — with your '
                    'location — and keeps everyday safety tools close at hand.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.7,
                      color: AppTheme.textBody,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'What it does'),
            _FeatureTile(
              icon: Icons.sos_outlined,
              title: 'Emergency SOS',
              subtitle: 'One hold alerts your guardians by SMS',
              onTap: () => context.push(AppRoutes.sos),
            ),
            _FeatureTile(
              icon: Icons.people_outline,
              title: 'Trusted contacts',
              subtitle: 'The people who receive your alerts',
              onTap: () => context.push(AppRoutes.contacts),
            ),
            _FeatureTile(
              icon: Icons.timer_outlined,
              title: 'Safety check-in',
              subtitle: 'Reminders that confirm you are safe',
              onTap: () => context.push(AppRoutes.checkInSettings),
            ),
            _FeatureTile(
              icon: Icons.mic_outlined,
              title: 'Voice notes',
              subtitle: 'Private on-device audio notes',
              onTap: () => context.push(AppRoutes.voiceRecording),
            ),
            _FeatureTile(
              icon: Icons.phone_outlined,
              title: 'Fake call',
              subtitle: 'A simulated incoming call, on demand',
              onTap: () => context.push(AppRoutes.fakeCall),
            ),
            const SizedBox(height: 8),
            const GhSectionTitle(title: 'Our promise'),
            GhCard(
              child: Column(
                children: [
                  Text(
                    'Safety should be simple, accessible and reliable.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      height: 1.6,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your data stays on this device. No accounts, no servers, '
                    'no tracking — everything works offline, for you.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.6,
                      color: AppTheme.textBody,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: appInfo.when(
                data: (info) => Text(
                  'GuardianHer ${info.version} (${info.buildNumber})',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textFaint,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GhCard(
        onTap: onTap,
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
              child: Icon(icon, color: AppTheme.guardianIndigo, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textBody,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}
