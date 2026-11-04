import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_router.dart';
import '../../../core/platform/home_widget.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../../shared/widgets/settings_section_header.dart';
import '../application/privacy_providers.dart';

/// Main settings screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appInfo = ref.watch(appInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SettingsSectionHeader(title: 'Safety'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Safety check-in'),
            subtitle: const Text(
              'Schedule reminders to confirm you are safe and message your '
              'trusted contacts',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.checkInSettings),
          ),
          ListTile(
            leading: const Icon(Icons.vibration),
            title: const Text('Shake SOS'),
            subtitle: const Text('Start SOS by shaking your phone, even when '
                'the app is closed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.shakeSosSettings),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Device administrator'),
            subtitle: const Text('Protect the app from force-stop and '
                'uninstall'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.deviceAdminSettings),
          ),
          const SettingsSectionHeader(title: 'Home screen'),
          const _SosWidgetTile(),
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
            title: const Text('Privacy policy (in-app)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacyPolicy),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Privacy Policy (online)'),
            subtitle: const Text('View published privacy policy'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              final uri = Uri.parse('https://guardianher.github.io/privacy-policy/');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Tile that asks the launcher to pin the home-screen SOS widget.
class _SosWidgetTile extends ConsumerWidget {
  const _SosWidgetTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.widgets_outlined),
      title: const Text('SOS widget'),
      subtitle: const Text('Add a home-screen shortcut that opens the SOS flow'),
      trailing: const Icon(Icons.add_circle_outline),
      onTap: () => _pin(context),
    );
  }

  Future<void> _pin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final supported = await canPinSosWidget();
    if (!supported) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Your launcher does not support adding widgets from here. You can '
            'add it from your home screen.',
          ),
        ),
      );
      return;
    }
    await pinSosWidget();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'If your launcher showed a widget preview, confirm it there. '
          'Otherwise add the widget from your home screen.',
        ),
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
      subtitle: const Text('Removes your trusted contacts, history and settings'),
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
          'This permanently removes your trusted contacts, emergency history '
          'and settings stored on this device. This cannot be undone.',
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

