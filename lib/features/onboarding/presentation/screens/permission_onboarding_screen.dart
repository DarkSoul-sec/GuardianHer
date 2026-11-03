import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/core/routing/route_guards.dart';
import 'package:guardianher/app/theme/app_theme.dart';
import 'package:guardianher/features/onboarding/application/permission_onboarding_providers.dart';
import 'package:guardianher/features/onboarding/application/permission_onboarding_notifier.dart';
import 'package:guardianher/features/shake/application/shake_sos_providers.dart';
import 'package:guardianher/shared/widgets/guardianher_design.dart';

class PermissionOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  ConsumerState<PermissionOnboardingScreen> createState() => _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends ConsumerState<PermissionOnboardingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(permissionOnboardingNotifierProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(permissionOnboardingNotifierProvider);
    final notifier = ref.read(permissionOnboardingNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(state: state),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  final isCurrent = index == state.currentStepIndex;
                  return _PermissionCard(
                    item: item,
                    isCurrent: isCurrent,
                    onGrant: () => notifier.requestPermission(item.step),
                    onSettings: () => notifier.openAppSettingsForPermission(item.step),
                  );
                },
              ),
            ),
            _ContinueButton(
              enabled: state.criticalPermissionsGranted,
              onPressed: () async {
                await RouteGuards.setOnboardingDone();
                if (context.mounted) context.go(AppRoutes.home);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.state});

  final PermissionOnboardingState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GhLogo(size: 40),
              const SizedBox(width: 12),
              Text(
                'Permissions Setup',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.guardianIndigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Grant permissions to enable all safety features',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textBody,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 8,
                    backgroundColor: AppTheme.lavenderSoft,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.guardianIndigo,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${state.grantedCount}/${state.totalCount}',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.guardianIndigo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.item,
    required this.isCurrent,
    required this.onGrant,
    required this.onSettings,
  });

  final PermissionStatusItem item;
  final bool isCurrent;
  final VoidCallback onGrant;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: item.isGranted
              ? AppTheme.successGreen.withValues(alpha: 0.5)
              : isCurrent
                  ? AppTheme.lavenderDeep
                  : AppTheme.borderLight,
          width: item.isGranted ? 1.5 : 1,
        ),
        boxShadow: AppTheme.softShadow(
          opacity: item.isGranted || isCurrent ? 0.12 : 0.07,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusIcon(item: item),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.guardianIndigo,
                          ),
                        ),
                      ),
                      if (item.isCritical)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.sosCoral.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'REQUIRED',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppTheme.sosCoral,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textBody,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionButtons(
                    item: item,
                    onGrant: onGrant,
                    onSettings: onSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.item});

  final PermissionStatusItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isGranted) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.successGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.check_rounded,
          color: AppTheme.successGreenDark,
          size: 24,
        ),
      );
    }

    if (item.isPending) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.lavenderSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppTheme.guardianIndigo,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.lavenderSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          item.icon,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({
    required this.item,
    required this.onGrant,
    required this.onSettings,
  });

  final PermissionStatusItem item;
  final VoidCallback onGrant;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Special handling for Shake SOS - it's an in-app feature toggle, not a system permission
    if (item.step == PermissionStep.shakeSos) {
      final shakeSosEnabled = ref.watch(shakeSosEnabledProvider);
      if (item.isGranted) {
        return Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.successGreenDark,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Enabled',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppTheme.successGreenDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: shakeSosEnabled,
              onChanged: isShakeSosSupported
                  ? (value) => ref
                      .read(shakeSosEnabledProvider.notifier)
                      .setEnabled(value)
                  : null,
              activeThumbColor: AppTheme.guardianIndigo,
              activeTrackColor:
                  AppTheme.lavenderMid.withValues(alpha: 0.6),
              inactiveThumbColor: AppTheme.textFaint,
              inactiveTrackColor: AppTheme.appBackgroundMuted,
            ),
          ],
        );
      }
      if (item.isPending) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onGrant,
          icon: const Icon(Icons.vibration, size: 18),
          label: const Text('Enable'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.guardianIndigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // Standard permission handling for other steps
    if (item.isGranted) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.successGreenDark,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Granted',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: AppTheme.successGreenDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (item.isPending) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onGrant,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Grant'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.guardianIndigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onSettings,
          icon: const Icon(Icons.settings_rounded, size: 18),
          label: const Text('Settings'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.guardianIndigo,
            side: const BorderSide(color: AppTheme.borderLight),
            backgroundColor: AppTheme.surfaceWhite,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text(
            enabled
                ? 'Continue to GuardianHer'
                : 'Grant required permissions first',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                enabled ? AppTheme.guardianIndigo : AppTheme.lavenderSoft,
            foregroundColor:
                enabled ? Colors.white : AppTheme.textFaint,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(27),
            ),
            disabledBackgroundColor: AppTheme.lavenderSoft,
            disabledForegroundColor: AppTheme.textFaint,
          ),
        ),
      ),
    );
  }
}
