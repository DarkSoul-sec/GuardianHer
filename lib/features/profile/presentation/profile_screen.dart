import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/guardianher_design.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/application/contacts_state.dart';

/// Profile tab — premium hub for user, safety, activity and settings.
///
/// All destinations reuse existing routes; nothing is removed.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsControllerProvider);
    final contactCount = switch (contacts) {
      ContactsLoaded(:final contacts) => contacts.length,
      _ => 0,
    };
    final appInfo = ref.watch(appInfoProvider);

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'Profile',
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Identity card
            GhCard(
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.lavenderSoft,
                      border: Border.all(color: AppTheme.lavenderMid, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'G',
                      style: GoogleFonts.inter(
                        color: AppTheme.guardianIndigo,
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GuardianHer User',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.guardianIndigo,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$contactCount trusted contact${contactCount == 1 ? '' : 's'}',
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
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'Safety'),
            _ProfileTile(
              icon: Icons.people_outline,
              title: 'Emergency contacts',
              subtitle: 'Manage trusted contacts',
              onTap: () => context.push(AppRoutes.contacts),
            ),
            _ProfileTile(
              icon: Icons.timer_outlined,
              title: 'Safety check-in',
              subtitle: 'Reminders and settings',
              onTap: () => context.push(AppRoutes.checkInSettings),
            ),
            _ProfileTile(
              icon: Icons.vibration_outlined,
              title: 'Shake SOS',
              subtitle: 'Shake to trigger emergency',
              onTap: () => context.push(AppRoutes.shakeSosSettings),
            ),
            const SizedBox(height: 8),
            const GhSectionTitle(title: 'Activity'),
            _ProfileTile(
              icon: Icons.history_outlined,
              title: 'Activity & history',
              subtitle: 'Emergencies and journeys',
              onTap: () => context.push(AppRoutes.history),
            ),
            _ProfileTile(
              icon: Icons.shield_outlined,
              title: 'Safety recorder',
              subtitle: 'Incident records',
              onTap: () => context.push(AppRoutes.safetyRecorder),
            ),
            const SizedBox(height: 8),
            const GhSectionTitle(title: 'Settings'),
            _ProfileTile(
              icon: Icons.notifications_outlined,
              title: 'Permissions',
              subtitle: 'Location, SMS, notifications',
              onTap: () => context.push(AppRoutes.permissions),
            ),
            _ProfileTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Device administrator',
              subtitle: 'Uninstall protection',
              onTap: () => context.push(AppRoutes.deviceAdminSettings),
            ),
            _ProfileTile(
              icon: Icons.settings_outlined,
              title: 'App settings',
              subtitle: 'Preferences and privacy',
              onTap: () => context.push(AppRoutes.settings),
            ),
            _ProfileTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              subtitle: 'How your data stays on-device',
              onTap: () => context.push(AppRoutes.privacyPolicy),
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

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
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
