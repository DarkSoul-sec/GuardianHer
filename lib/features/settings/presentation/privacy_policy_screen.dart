import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';

/// GuardianHer Privacy Policy.
///
/// Plain-language, scrollable, sectioned. All technical claims below match
/// the actual implementation (on-device storage, no backend, no analytics).
/// Legal wording stays editable here; the structure is final.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// Edit when the copy is legally reviewed.
  static const String lastUpdated = 'November 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'Privacy Policy',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Privacy Policy',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last updated: $lastUpdated',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _Section(
              number: '1',
              title: 'Overview',
              body: 'GuardianHer is a personal safety application that helps '
                  'you alert people you trust in an emergency. The app is '
                  'designed to work fully on your device: your contacts, '
                  'settings and safety records are stored on your phone, not '
                  'on our servers — because we operate no servers for this app.',
            ),
            const _Section(
              number: '2',
              title: 'Information We Use',
              body: 'GuardianHer uses only the information you enter yourself: '
                  'the names and phone numbers of your trusted contacts, your '
                  'safety preferences and settings, and content you create in '
                  'the app such as voice notes. The app collects no analytics '
                  'and serves no advertising.',
            ),
            const _Section(
              number: '3',
              title: 'Location Information',
              body: 'Your location is captured only when you ask for it — when '
                  'you activate SOS, confirm a safety check-in, or choose to '
                  'share your location. GuardianHer does not track your '
                  'location in the background and does not request background '
                  'location access. Each capture is a one-time fix used for '
                  'the emergency message or share you approved.',
            ),
            const _Section(
              number: '4',
              title: 'Emergency Features',
              body: 'When you activate SOS — from the SOS button, Shake SOS, '
                  'the Quick Settings tile, or the home-screen widget — the '
                  'app can automatically send SMS alerts with your location to '
                  'the emergency contacts you selected, and can place you one '
                  'tap away from calling emergency services (112). Simulated '
                  'features such as Fake Call never place real calls, and '
                  'voice notes only record while you visibly keep the '
                  'recording screen open.',
            ),
            const _Section(
              number: '5',
              title: 'Trusted Contacts',
              body: 'Trusted contacts are people you add yourself. Their names '
                  'and phone numbers are stored securely on your device using '
                  'the system keystore. They receive messages only when you '
                  'trigger an emergency or explicitly share something — the '
                  'app never contacts them on its own.',
            ),
            const _Section(
              number: '6',
              title: 'Permissions',
              body: 'GuardianHer requests access only to what its features '
                  'need: location (emergency location capture), SMS (emergency '
                  'alerts you arm), notifications (SOS and reminder alerts), '
                  'microphone (only for voice notes you start yourself), and '
                  'optionally display-over-other-apps (only so Shake SOS can '
                  'open the app from a locked screen, if you enable it). '
                  'Device administrator is strictly opt-in and is used only to '
                  'resist uninstallation during an emergency — the app never '
                  'locks or wipes your device. You can deny any permission; '
                  'the related feature will simply explain what is unavailable.',
            ),
            const _Section(
              number: '7',
              title: 'Data Storage & Security',
              body: 'Everything GuardianHer keeps — trusted contacts, settings, '
                  'safety records and voice notes — lives in the app’s private '
                  'on-device storage, with sensitive items held in the '
                  'system-backed secure storage (Android Keystore). Voice '
                  'recordings stay on this device until you delete them '
                  'individually or use Delete All Data. Other apps '
                  'cannot read this data.',
            ),
            const _Section(
              number: '8',
              title: 'Data Sharing',
              body: 'GuardianHer transmits nothing to any server, analytics '
                  'service, advertiser or cloud. The only transmissions are '
                  'the ones you trigger: SMS alerts to your chosen guardians, '
                  'a phone call you place, or a file you share yourself '
                  'through the Android share sheet.',
            ),
            const _Section(
              number: '9',
              title: 'User Control',
              body: 'You control everything: which contacts are emergency '
                  'contacts, which permissions are granted, whether Shake SOS '
                  'or the device administrator is enabled, and when any '
                  'recording, sharing or alert happens. Nothing safety-related '
                  'runs without your action.',
            ),
            const _Section(
              number: '10',
              title: 'Data Deletion',
              body: 'You can delete individual contacts, voice notes and '
                  'records inside the app at any time. The “Delete all local '
                  'data” option in Settings wipes every GuardianHer record — '
                  'contacts, settings, safety incidents and voice recordings, '
                  'including their audio files — from this device. '
                  'Uninstalling the app also removes its private data.',
            ),
            const _Section(
              number: '11',
              title: 'Changes to This Policy',
              body: 'If this policy changes, the updated version will be '
                  'published here with a new “Last updated” date. Significant '
                  'changes will additionally be highlighted inside the app.',
            ),
            const _Section(
              number: '12',
              title: 'Contact',
              body: 'Questions about this policy or your data can be sent to '
                  'guidemytechno@gmail.com. Please include "GuardianHer '
                  'Privacy" in the subject line so your message is routed '
                  'correctly.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GhCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.lavenderSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    number,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.7,
                color: AppTheme.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
