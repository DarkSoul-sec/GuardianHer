import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Whether GuardianHer is currently an active device administrator.
final deviceAdminActiveProvider = FutureProvider<bool>((ref) {
  return ref.watch(deviceAdminServiceProvider).isActive();
});

/// Device-administrator settings (Android only).
///
/// Being an active device administrator blocks uninstall and disables the
/// system's "Force stop" button until the admin is deactivated. That keeps
/// the Shake SOS detector alive when the app is closed and makes the app much
/// harder to remove. It does NOT turn the app into a system app and never
/// uses lock-screen or wipe policies. The user can always deactivate it from
/// Settings > Device admin apps.
class DeviceAdminSettingsScreen extends ConsumerStatefulWidget {
  const DeviceAdminSettingsScreen({super.key});

  @override
  ConsumerState<DeviceAdminSettingsScreen> createState() =>
      _DeviceAdminSettingsScreenState();
}

class _DeviceAdminSettingsScreenState
    extends ConsumerState<DeviceAdminSettingsScreen>
    with WidgetsBindingObserver {
  bool _busy = false;

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
    // Refresh after returning from the system activation screen.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(deviceAdminActiveProvider);
    }
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    await ref.read(deviceAdminServiceProvider).requestActivation();
    if (!mounted) return;
    ref.invalidate(deviceAdminActiveProvider);
    setState(() => _busy = false);
  }

  Future<void> _deactivate() async {
    setState(() => _busy = true);
    await ref.read(deviceAdminServiceProvider).deactivate();
    if (!mounted) return;
    ref.invalidate(deviceAdminActiveProvider);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = ref.watch(deviceAdminActiveProvider);

    if (defaultTargetPlatform != TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device administrator')),
        body: const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Not available'),
          subtitle: Text('Device administrator is an Android-only feature.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Device administrator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          active.when(
            data: (isActive) => _StatusBanner(active: isActive),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const ListTile(
              leading: Icon(Icons.error_outline),
              title: Text('Could not read the admin status'),
            ),
          ),
          const SizedBox(height: 16),
          active.when(
            data: (isActive) => isActive
                ? FilledButton.tonalIcon(
                    onPressed: _busy ? null : _deactivate,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Deactivate device administrator'),
                  )
                : FilledButton.icon(
                    onPressed: _busy ? null : _activate,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Activate device administrator'),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          Text('What this gives you', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Benefit(
            icon: Icons.block_outlined,
            title: 'Cannot be force-stopped',
            description:
                'While active, the system disables the "Force stop" button '
                'and apps cannot be stopped from the app info page.',
          ),
          const _Benefit(
            icon: Icons.delete_outline,
            title: 'Cannot be easily uninstalled',
            description:
                'Android refuses to uninstall until the admin is deactivated '
                'first, so the app survives even if the phone is in someone '
                'else\'s hands.',
          ),
          const _Benefit(
            icon: Icons.vibration,
            title: 'Keeps Shake SOS alive',
            description:
                'With force-stop blocked, aggressive launchers (MIUI) cannot '
                'kill the shake detector when you clear recent apps.',
          ),
          const Divider(height: 32),
          Text('What it does NOT do', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Benefit(
            icon: Icons.warning_amber_outlined,
            title: 'Not a system app',
            description:
                'GuardianHer does not become a system or rooted app. Battery '
                'optimization and autostart whitelists are still recommended.',
          ),
          const _Benefit(
            icon: Icons.screen_lock_portrait,
            title: 'Never locks or wipes',
            description:
                'GuardianHer declares no device policies. It can only hold '
                'admin status — it cannot lock your screen or wipe your phone.',
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_open_outlined),
            title: const Text('Removing it is always possible'),
            subtitle: const Text(
              'Anyone with the phone can go to Settings > Device admin apps '
              'and deactivate GuardianHer at any time. There is no password '
              'wall — this is by design so the feature is never trapping.',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.tertiary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.verified_user : Icons.gpp_bad_outlined,
            color: color,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              active
                  ? 'GuardianHer is an active device administrator.'
                  : 'GuardianHer is not a device administrator.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}