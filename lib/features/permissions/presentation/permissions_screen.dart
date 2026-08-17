import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../shared/widgets/feature_error.dart';
import '../application/permissions_providers.dart';
import '../domain/permission_entry.dart';

/// Displays the status and rationale for every permission the app may need.
///
/// Request actions are only shown for permissions that are actually required
/// by the current features ([PermissionEntry.requestable]); none are in Phase 1.
class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(permissionsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => FeatureError(
          message: 'Permission status could not be loaded.',
          onRetry: () => ref.invalidate(permissionsControllerProvider),
        ),
        data: (list) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) =>
              _PermissionTile(entry: list[index]),
        ),
      ),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({required this.entry});

  final PermissionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final descriptor = entry.descriptor;
    final statusLabel = _statusLabel(entry.status);
    final statusColor = _statusColor(theme, entry.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(descriptor.icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(descriptor.title,
                      style: theme.textTheme.titleMedium),
                ),
                Semantics(
                  label: statusLabel,
                  child: Chip(
                    label: Text(statusLabel),
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    labelStyle: TextStyle(color: statusColor),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(descriptor.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (entry.permanentlyDenied)
                  TextButton(
                    onPressed: () => ref
                        .read(permissionsControllerProvider.notifier)
                        .openSettings(),
                    child: const Text('Open Settings'),
                  ),
                if (entry.requestable && !entry.permanentlyDenied)
                  FilledButton.tonal(
                    onPressed: () => ref
                        .read(permissionsControllerProvider.notifier)
                        .request(entry.descriptor.permission),
                    child: const Text('Allow'),
                  ),
                if (!entry.requestable && !entry.permanentlyDenied)
                  const Text(
                    'Not required yet',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(PermissionStatus status) {
  return switch (status) {
    PermissionStatus.granted => 'Granted',
    PermissionStatus.denied => 'Not granted',
    PermissionStatus.permanentlyDenied => 'Denied',
    PermissionStatus.restricted => 'Restricted',
    PermissionStatus.limited => 'Limited',
  };
}

Color _statusColor(ThemeData theme, PermissionStatus status) {
  return switch (status) {
    PermissionStatus.granted => Colors.green.shade600,
    PermissionStatus.denied => theme.colorScheme.outline,
    PermissionStatus.permanentlyDenied => theme.colorScheme.error,
    PermissionStatus.restricted => theme.colorScheme.tertiary,
    PermissionStatus.limited => theme.colorScheme.secondary,
  };
}