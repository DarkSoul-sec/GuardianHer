import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/check_in/application/check_in_providers.dart';
import '../features/contacts/application/contacts_providers.dart';
import '../features/contacts/application/contacts_state.dart';
import '../features/contacts/domain/trusted_contact.dart';
import '../features/location/application/location_providers.dart';
import '../features/sos/application/sos_providers.dart';
import '../shared/widgets/guardianher_design.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// GuardianHer Home — premium safety dashboard.
///
/// Hierarchy: safety status → header → safety card (SOS center) →
/// quick actions → trusted contacts. Scrollable, responsive, no fixed
/// coordinates. All actions reuse existing providers/controllers.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);
    final checkIn = ref.watch(checkInControllerProvider);

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SafetyStatusLine(locationLabel: _locationLabel(location)),
              const SizedBox(height: 14),
              const _Header(),
              const SizedBox(height: 18),
              _SafetyCard(lastCheckIn: _lastCheckInText(checkIn)),
              const SizedBox(height: 24),
              const GhSectionTitle(title: 'Quick Actions'),
              const _QuickActionsRow(),
              const SizedBox(height: 24),
              _TrustedContactsSection(),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Your safety data stays on this device.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _locationLabel(dynamic location) {
    try {
      final label = location.statusLabel as String?;
      if (label != null && label.isNotEmpty) return label;
    } catch (_) {}
    return 'Current Location';
  }

  String _lastCheckInText(dynamic checkIn) {
    try {
      final at = checkIn.settings.lastAcknowledgedAt as DateTime?;
      if (at == null) return 'Last check-in: not yet';
      final diff = DateTime.now().difference(at);
      if (diff.inMinutes < 1) return 'Last check-in: just now';
      if (diff.inMinutes < 60) return 'Last check-in: ${diff.inMinutes} min ago';
      if (diff.inHours < 24) return 'Last check-in: ${diff.inHours}h ago';
      return 'Last check-in: ${diff.inDays}d ago';
    } catch (_) {
      return 'Last check-in: —';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Safety status line
// ─────────────────────────────────────────────────────────────────────────────

class _SafetyStatusLine extends StatelessWidget {
  const _SafetyStatusLine({required this.locationLabel});

  final String locationLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const GhSafetyDot(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'You are safe • $locationLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textBody,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: logo + GuardianHer + bell + avatar
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const GhLogo(size: 48),
        const SizedBox(width: 12),
        Text(
          'GuardianHer',
          style: GoogleFonts.inter(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.guardianIndigo,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        _HeaderIconButton(
          icon: Icons.notifications_outlined,
          onTap: () => context.push(AppRoutes.checkIn),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => context.push(AppRoutes.profile),
          child: Container(
            width: 44,
            height: 44,
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
                fontSize: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surfaceWhite,
            border: Border.all(color: AppTheme.borderLight),
            boxShadow: AppTheme.softShadow(opacity: 0.06),
          ),
          child: Icon(icon, size: 22, color: AppTheme.guardianIndigo),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Safety card with central SOS
// ─────────────────────────────────────────────────────────────────────────────

class _SafetyCard extends ConsumerWidget {
  const _SafetyCard({required this.lastCheckIn});

  final String lastCheckIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GhCard(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.lavenderSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 28,
              color: AppTheme.guardianIndigo,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'You are safe',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppTheme.guardianIndigo,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$lastCheckIn • Safe area',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textBody,
            ),
          ),
          const SizedBox(height: 24),
          GhSosButton(
            onTap: () => context.push(AppRoutes.sos),
            onHoldComplete: () {
              ref.read(sosControllerProvider.notifier).startSos();
              context.push(AppRoutes.sos);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions (all wired: location flow, Fake Call, Voice Recording)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GhQuickAction(
            icon: Icons.radar_outlined,
            label: 'Share Live\nLocation',
            onTap: () => context.push(AppRoutes.location),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GhQuickAction(
            icon: Icons.phone_outlined,
            label: 'Fake Call\nSimulate a call',
            onTap: () => context.push(AppRoutes.fakeCall),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GhQuickAction(
            icon: Icons.mic_outlined,
            label: 'Record Audio\nRecord a note',
            onTap: () => context.push(AppRoutes.voiceRecording),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trusted contacts (real data)
// ─────────────────────────────────────────────────────────────────────────────

class _TrustedContactsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contactsControllerProvider);
    final contacts = switch (state) {
      ContactsLoaded(:final contacts) => contacts,
      _ => const <TrustedContact>[],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Trusted Contacts',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.guardianIndigo,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => context.push(AppRoutes.contacts),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.guardianIndigo,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.guardianIndigo,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (contacts.isEmpty)
          GhCard(
            onTap: () => context.push(AppRoutes.contactsAdd),
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
                    Icons.person_add_outlined,
                    color: AppTheme.guardianIndigo,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Add people who can be contacted\nduring an emergency.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textBody,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return GhContactCard(
                  name: contact.name,
                  onCall: () => _callContact(context, ref, contact),
                  onTap: () => context.push(AppRoutes.contacts),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _callContact(
    BuildContext context,
    WidgetRef ref,
    TrustedContact contact,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(sosActionsControllerProvider.notifier)
        .callContact(contact);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.fold((o) => o.message, (f) => f.message),
        ),
      ),
    );
  }
}
