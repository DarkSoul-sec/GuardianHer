import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/creator_links.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';

/// About Me — the creator behind GuardianHer.
///
/// Personal, compact, same light design system. Social cards render only for
/// configured links; unconfigured platforms are hidden, never faked.
class AboutMeScreen extends StatelessWidget {
  const AboutMeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'About Me',
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
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.lavenderDeep.withValues(alpha: 0.6),
                        width: 3,
                      ),
                      boxShadow: AppTheme.softShadow(opacity: 0.15),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/brand/creator.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, _) => Container(
                          color: AppTheme.lavenderSoft,
                          alignment: Alignment.center,
                          child: Text(
                            'A',
                            style: GoogleFonts.inter(
                              color: AppTheme.guardianIndigo,
                              fontWeight: FontWeight.w800,
                              fontSize: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    CreatorLinks.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CreatorLinks.role,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textBody,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    CreatorLinks.tags,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.6,
                      color: AppTheme.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'About Me'),
            GhCard(
              child: Text(
                CreatorLinks.aboutMe,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.7,
                  color: AppTheme.textBody,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'What I Do'),
            const _WhatIDoGrid(),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'My Journey'),
            GhCard(
              child: Text(
                CreatorLinks.journey,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.7,
                  color: AppTheme.textBody,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'Connect with me'),
            _SocialCard(
              icon: Icons.camera_alt_outlined,
              platform: 'Instagram',
              handle: _handleOf(CreatorLinks.instagramUrl),
              url: CreatorLinks.instagramUrl,
            ),
            _SocialCard(
              icon: Icons.work_outline,
              platform: 'LinkedIn',
              handle: _handleOf(CreatorLinks.linkedInUrl),
              url: CreatorLinks.linkedInUrl,
            ),
            _SocialCard(
              icon: Icons.code_outlined,
              platform: 'GitHub',
              handle: _handleOf(CreatorLinks.gitHubUrl),
              url: CreatorLinks.gitHubUrl,
            ),
            _SocialCard(
              icon: Icons.mail_outline,
              platform: 'Email',
              handle: CreatorLinks.emailAddress.isEmpty
                  ? ''
                  : CreatorLinks.emailAddress,
              url: CreatorLinks.emailAddress.isEmpty
                  ? ''
                  : 'mailto:${CreatorLinks.emailAddress}',
            ),
            const SizedBox(height: 20),
            GhCard(
              child: Column(
                children: [
                  Text(
                    CreatorLinks.taglineName,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CreatorLinks.taglineCreator,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a readable handle for a configured URL, or '' to hide the card.
  static String _handleOf(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    final segments =
        uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    if (segments.isNotEmpty) return '@${segments.last}';
    return uri?.host ?? url;
  }
}

class _WhatIDoGrid extends StatelessWidget {
  const _WhatIDoGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.computer_outlined, 'Technology & Cybersecurity',
          'Exploring cybersecurity, ethical hacking and secure technology.'),
      (Icons.shield_outlined, 'GuardianHer',
          'Building practical technology focused on personal safety.'),
      (Icons.camera_alt_outlined, 'Photography & Creativity',
          'Capturing moments and exploring visual storytelling.'),
      (Icons.edit_outlined, 'Poetry & Writing',
          'Writing poetry and expressing ideas through words.'),
    ];
    return Column(
      children: [
        for (var i = 0; i < items.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < items.length ? 12 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + 2 && j < items.length; j++) ...[
                  Expanded(
                    child: _WhatIDoCard(
                      icon: items[j].$1,
                      title: items[j].$2,
                      subtitle: items[j].$3,
                    ),
                  ),
                  if (j == i && i + 1 < items.length)
                    const SizedBox(width: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _WhatIDoCard extends StatelessWidget {
  const _WhatIDoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return GhCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.lavenderSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppTheme.guardianIndigo, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.guardianIndigo,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.textBody,
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialCard extends StatelessWidget {
  const _SocialCard({
    required this.icon,
    required this.platform,
    required this.handle,
    required this.url,
  });

  final IconData icon;
  final String platform;
  final String handle;
  final String url;

  @override
  Widget build(BuildContext context) {
    // Unconfigured platforms stay hidden — never show a dead link.
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GhCard(
        onTap: () => _open(context, url),
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
                    platform,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  if (handle.isNotEmpty)
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textFaint,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppTheme.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }
}
