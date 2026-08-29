import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/contacts/application/contacts_providers.dart';
import '../features/contacts/application/contacts_state.dart';
import '../features/sos/application/sos_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../shared/widgets/premium_components.dart';

/// Premium safety dashboard — the main landing screen.
///
/// Layout: ambient background, app logo, greeting with protection status,
/// large SOS button, safety status card, quick-action grid.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsControllerProvider);
    final contactCount = switch (contacts) {
      ContactsLoaded(:final contacts) => contacts.length,
      _ => 0,
    };

    return Scaffold(
      backgroundColor: AppTheme.navyBase,
      body: AmbientBackground(
        centerGlowColor: AppTheme.violet,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                const SizedBox(height: 4),
                const _Greeting(),
                const SizedBox(height: 32),
                const _SosSection(),
                const SizedBox(height: 28),
                _SafetyStatusCard(contactCount: contactCount),
                const SizedBox(height: 28),
                const PremiumSectionHeader(title: 'Quick Actions'),
                const _QuickActionsGrid(),
                const SizedBox(height: 32),
                const _PrivacyNote(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header row: logo + settings icon
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppTheme.violet.withValues(alpha: 0.15),
            border: Border.all(
              color: AppTheme.violet.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/brand/logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const Spacer(),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.glassFill,
            border: Border.all(
              color: AppTheme.glassBorder,
              width: 0.5,
            ),
          ),
          child: IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            color: AppTheme.textSecondary,
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Greeting + status line
// ─────────────────────────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You\'re Safe',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.successGreen,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.successGreen.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Protection Active',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button Section
// ─────────────────────────────────────────────────────────────────────────────

class _SosSection extends ConsumerStatefulWidget {
  const _SosSection();

  @override
  ConsumerState<_SosSection> createState() => _SosSectionState();
}

class _SosSectionState extends ConsumerState<_SosSection> {
  bool _isArmed = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SosButton(
        onPressed: _isArmed
            ? () {}
            : () {
                setState(() => _isArmed = true);
                ref.read(sosControllerProvider.notifier).startSos();
                context.push(AppRoutes.sos).whenComplete(() {
                  if (mounted) setState(() => _isArmed = false);
                });
              },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Safety Status Card
// ─────────────────────────────────────────────────────────────────────────────

class _SafetyStatusCard extends StatelessWidget {
  const _SafetyStatusCard({required this.contactCount});

  final int contactCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      elevated: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSectionHeader(
            title: 'Safety Status',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  color: AppTheme.successGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const StatusIndicator(
            label: 'Protection status',
            level: StatusLevel.active,
            trailing: Text('ON',
                style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ),
          const SizedBox(height: 10),
          const StatusIndicator(
            label: 'Location services',
            level: StatusLevel.active,
            trailing: Text('ON',
                style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ),
          const SizedBox(height: 10),
          StatusIndicator(
            label: 'Emergency contacts',
            level: contactCount > 0
                ? StatusLevel.active
                : StatusLevel.warning,
            trailing: Text(
              '$contactCount connected',
              style: TextStyle(
                color: contactCount > 0
                    ? AppTheme.successGreen
                    : AppTheme.warningAmber,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const StatusIndicator(
            label: 'Device status',
            level: StatusLevel.active,
            trailing: Text('Secure',
                style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions Grid
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: [
        QuickActionCard(
          icon: Icons.share_location_outlined,
          label: 'Share\nLocation',
          onTap: () => context.push(AppRoutes.location),
        ),
        QuickActionCard(
          icon: Icons.timer_outlined,
          label: 'Safety\nTimer',
          color: AppTheme.infoCyan,
          onTap: () => context.push(AppRoutes.checkInSettings),
        ),
        QuickActionCard(
          icon: Icons.people_outline,
          label: 'Emergency\nContacts',
          color: AppTheme.magenta,
          onTap: () => context.push(AppRoutes.contacts),
        ),
        QuickActionCard(
          icon: Icons.local_phone_outlined,
          label: 'Emergency\nCall',
          color: AppTheme.sosRed,
          onTap: () => context.push(AppRoutes.sos),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Privacy Note
// ─────────────────────────────────────────────────────────────────────────────

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Your safety data is private and visible only to you.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
    );
  }
}
