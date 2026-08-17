import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../../shared/widgets/settings_section_header.dart';
import '../../auth/application/app_lock_providers.dart';
import '../../auth/domain/app_lock_status.dart';
import '../application/privacy_providers.dart';

/// Main settings screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockControllerProvider);
    final appInfo = ref.watch(appInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SettingsSectionHeader(title: 'Security'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Security'),
            subtitle: Text(
              lock.status == AppLockStatus.needsSetup
                  ? 'App lock is not set up'
                  : 'App lock and biometric unlock',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.security),
          ),
          const SettingsSectionHeader(title: 'Permissions'),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Permissions'),
            subtitle: const Text('View permission status and rationale'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.permissions),
          ),
          const SettingsSectionHeader(title: 'Privacy'),
          _DeleteDataTile(),
          const SettingsSectionHeader(title: 'Accessibility'),
          const ListTile(
            leading: Icon(Icons.text_fields),
            title: Text('Font scaling'),
            subtitle: Text('Follows your system font size setting'),
          ),
          const ListTile(
            leading: Icon(Icons.animation_outlined),
            title: Text('Reduced motion'),
            subtitle: Text('Follows your system motion preferences'),
          ),
          const SettingsSectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('GuardianHer'),
            subtitle: Text(appInfo.when(
              data: (info) => 'Version ${info.version}',
              loading: () => 'Version…',
              error: (_, _) => 'Version unavailable',
            )),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacyPolicy),
          ),
        ],
      ),
    );
  }
}

class _DeleteDataTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeleting = ref.watch(privacyControllerProvider);
    return ListTile(
      enabled: !isDeleting,
      leading: Icon(
        Icons.delete_forever_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        'Delete all local data',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: const Text('Removes your PIN, settings and stored information'),
      onTap: isDeleting ? null : () => _confirmDelete(context, ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all local data?'),
        content: const Text(
          'This permanently removes your app lock PIN, security settings and '
          'all stored information on this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await ref.read(privacyControllerProvider.notifier).deleteAllLocalData();
    if (result is! Ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Local data could not be deleted.')),
      );
    }
  }
}