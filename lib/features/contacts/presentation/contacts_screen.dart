import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/result/result.dart';
import '../../../shared/widgets/feature_error.dart';
import '../application/contacts_providers.dart';
import '../application/contacts_state.dart';
import '../domain/trusted_contact.dart';

/// Trusted emergency contacts.
///
/// The user manages contacts manually (name + phone number) — GuardianHer does
/// not request the device address book. Full phone numbers are never shown;
/// cards display a masked form, and mutations require confirmation.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contactsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Contacts')),
      floatingActionButton: switch (state) {
        ContactsLoaded(:final contacts) when contacts.isNotEmpty =>
          FloatingActionButton.extended(
            onPressed: state.saving
                ? null
                : () => context.push(AppRoutes.contactsAdd),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add contact'),
          ),
        _ => null,
      },
      body: switch (state) {
        ContactsLoading() =>
          const Center(child: CircularProgressIndicator()),
        ContactsError(:final failure) => FeatureError(
            message: failure.message,
            onRetry: () =>
                ref.read(contactsControllerProvider.notifier).reload(),
          ),
        ContactsLoaded(:final contacts) when contacts.isEmpty =>
          _ContactsEmptyState(
            onAdd: () => context.push(AppRoutes.contactsAdd),
          ),
        ContactsLoaded(:final contacts, :final saving) => _ContactList(
            contacts: contacts,
            saving: saving,
          ),
      },
    );
  }
}

/// Shown when no trusted contacts exist yet.
class _ContactsEmptyState extends StatelessWidget {
  const _ContactsEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No trusted contacts yet',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add the people who can be contacted during an emergency. '
              'Their details are stored securely on this device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add contact'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reorderable list of trusted-contact cards.
class _ContactList extends ConsumerWidget {
  const _ContactList({required this.contacts, required this.saving});

  final List<TrustedContact> contacts;
  final bool saving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'People who can be contacted during an emergency.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            itemCount: contacts.length,
            onReorderItem: saving
                ? null
                : (oldIndex, newIndex) => _reorder(ref, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return Padding(
                key: ValueKey(contact.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: _ContactCard(contact: contact, enabled: !saving),
              );
            },
          ),
        ),
      ],
    );
  }

  void _reorder(WidgetRef ref, int oldIndex, int newIndex) {
    final reordered = List.of(contacts);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    ref
        .read(contactsControllerProvider.notifier)
        .reorderContacts([for (final contact in reordered) contact.id]);
  }
}

/// A single trusted-contact card with masked phone and edit/delete actions.
class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.contact, required this.enabled});

  final TrustedContact contact;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final last4 = contact.phoneNumber.substring(contact.phoneNumber.length - 4);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contact.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Semantics(
                        label: 'Phone number ending $last4',
                        child: Text(
                          _maskPhone(contact.phoneNumber),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text('Priority ${contact.priority}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: enabled
                      ? () => context.push(AppRoutes.contactsEdit(contact.id))
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: enabled ? () => _confirmDelete(context, ref) : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete trusted contact?'),
        content: Text(
          '${contact.name} will no longer receive emergency alerts from '
          'GuardianHer.',
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

    final result = await ref
        .read(contactsControllerProvider.notifier)
        .deleteContact(contact.id);
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

/// Masks a normalized phone number, revealing only the last four digits.
String _maskPhone(String normalized) {
  if (normalized.length <= 4) return normalized;
  final last4 = normalized.substring(normalized.length - 4);
  return '${'•' * (normalized.length - 4)}$last4';
}