import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:guardianher/core/platform/shake_sos_service.dart';
import 'package:guardianher/core/routing/route_guards.dart';
import 'package:guardianher/app/theme/app_theme.dart';
import 'package:guardianher/features/onboarding/application/permission_onboarding_providers.dart';
import 'package:guardianher/features/onboarding/application/permission_onboarding_notifier.dart';
import 'package:guardianher/features/shake/application/shake_sos_providers.dart';

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
      backgroundColor: AppTheme.navyBase,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(state: state),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
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
                if (context.mounted) context.go('/home');
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
          Text(
            'Permissions Setup',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Grant permissions to enable all safety features',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: state.progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: AppTheme.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.violet),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${state.grantedCount}/${state.totalCount}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.violet,
                      fontWeight: FontWeight.w600,
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: item.isGranted
            ? AppTheme.violet.withValues(alpha: 0.15)
            : isCurrent
                ? AppTheme.surfaceVariant.withValues(alpha: 0.5)
                : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isGranted
              ? AppTheme.violet
              : isCurrent
                  ? AppTheme.violet.withValues(alpha: 0.5)
                  : AppTheme.glowDivider,
          width: item.isGranted ? 2 : 1,
        ),
        boxShadow: item.isGranted || isCurrent
            ? [
                BoxShadow(
                  color: AppTheme.violet.withValues(alpha: 0.1),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      if (item.isCritical)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.violet.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'REQUIRED',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppTheme.violet,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
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
          color: AppTheme.violet.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_rounded,
          color: AppTheme.violet,
          size: 24,
        ),
      );
    }

    if (item.isPending) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.violet.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.violet),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.violet.withValues(alpha: 0.1),
        shape: BoxShape.circle,
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
            Icon(
              Icons.check_circle_rounded,
              color: AppTheme.violet,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Enabled',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.violet,
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
              activeThumbColor: AppTheme.violet,
              activeTrackColor: AppTheme.violet.withValues(alpha: 0.3),
              inactiveThumbColor: AppTheme.textDisabled,
              inactiveTrackColor: AppTheme.surfaceVariant,
            ),
          ],
        );
      }
      if (item.isPending) {
        return const SizedBox.shrink();
      }
      return FilledButton.icon(
        onPressed: onGrant,
        icon: const Icon(Icons.vibration, size: 18),
        label: const Text('Enable'),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.violet,
          foregroundColor: AppTheme.textOnViolet,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    // Standard permission handling for other steps
    if (item.isGranted) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppTheme.violet,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Granted',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.violet,
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
              backgroundColor: AppTheme.violet,
              foregroundColor: AppTheme.textOnViolet,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
            foregroundColor: AppTheme.textSecondary,
            side: BorderSide(color: AppTheme.glowDivider),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text(
            enabled ? 'Continue to GuardianHer' : 'Grant required permissions first',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: enabled ? AppTheme.violet : AppTheme.surfaceVariant,
            foregroundColor: enabled ? AppTheme.textOnViolet : AppTheme.textDisabled,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            disabledBackgroundColor: AppTheme.surfaceVariant,
            disabledForegroundColor: AppTheme.textDisabled,
          ),
        ),
      ),
    );
  }
}