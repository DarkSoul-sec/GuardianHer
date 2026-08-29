import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/result/result.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/application/contacts_state.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../application/check_in_providers.dart';
import '../domain/check_in_delivery_status.dart';
import '../domain/check_in_interval.dart';
import '../domain/check_in_settings.dart';

/// Safety Check-In configuration screen.
///
/// The user opts in, chooses an interval and picks the trusted contacts who
/// receive the check-in message. Saving with check-in on requests notification
/// permission in context (required to schedule reminders) and starts the
/// reminder schedule; saving with it off cancels it. Plain language, no
/// jargon.
class CheckInSettingsScreen extends ConsumerStatefulWidget {
  const CheckInSettingsScreen({super.key});

  @override
  ConsumerState<CheckInSettingsScreen> createState() =>
      _CheckInSettingsScreenState();
}

class _CheckInSettingsScreenState extends ConsumerState<CheckInSettingsScreen> {
  late bool _enabled;
  late CheckInInterval _interval;
  late Set<String> _selectedIds;

  /// Whether local form state has been seeded from PERSISTED settings.
  ///
  /// The controller loads asynchronously; [initState] always sees the
  /// disabled default first. Without this seed-once sync the form silently
  /// shows/starts from a wrong configuration whenever the screen opens
  /// before storage finishes loading (observed on device).
  bool _seeded = false;

  // Local edits win over persistence once the user touches the form.
  bool _edited = false;

  void _seedFrom(CheckInSettings settings) {
    _enabled = settings.enabled;
    _interval = settings.interval;
    _selectedIds = settings.recipientContactIds.toSet();
    _seeded = true;
  }

  @override
  void initState() {
    super.initState();
    _seedFrom(ref.read(checkInControllerProvider).settings);
    // Escalation + alarm re-assertion run on every open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checkInControllerProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkInControllerProvider);
    if (!_seeded || (!_edited && state.loaded)) {
      _seedFrom(state.settings);
    }
    final theme = Theme.of(context);
    final contactsState = ref.watch(contactsControllerProvider);
    final contacts = switch (contactsState) {
      ContactsLoaded(:final contacts) => contacts,
      _ => const <TrustedContact>[],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Safety check-in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.settings.enabled && state.loaded)
            _CheckInStatusCard(settings: state.settings),
          SwitchListTile(
            title: const Text('Safety check-in'),
            subtitle: const Text(
              'Remind me to confirm I am safe, and send a check-in message '
              'to my trusted contacts.',
            ),
            value: _enabled,
            onChanged: state.isWorking
                ? null
                : (value) => setState(() {
                    _edited = true;
                    _enabled = value;
                  }),
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            Text('Check-in every', style: theme.textTheme.labelLarge),
            DropdownButtonFormField<CheckInInterval>(
              initialValue: _interval,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: [
                for (final interval in CheckInInterval.selectable)
                  DropdownMenuItem(
                    value: interval,
                    child: Text(interval.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _edited = true;
                    _interval = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Trusted contacts to notify',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (contacts.isEmpty)
              Card(
                child: ListTile(
                  title: const Text('No trusted contacts yet'),
                  subtitle: const Text(
                    'Add at least one trusted contact to receive your '
                    'check-in messages.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.contacts),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final contact in contacts)
                      CheckboxListTile(
                        title: Text(contact.name),
                        value: _selectedIds.contains(contact.id),
                        onChanged: (checked) => setState(() {
                          _edited = true;
                          if (checked == true) {
                            _selectedIds.add(contact.id);
                          } else {
                            _selectedIds.remove(contact.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (_enabled && _selectedIds.isEmpty)
              Text(
                'Choose at least one trusted contact.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
          if (state.statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.statusMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.isWorking
                ? null
                : () => _save(context, contacts),
            child: Text(_enabled ? 'Start check-in' : 'Turn off check-in'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    List<TrustedContact> contacts,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(checkInControllerProvider.notifier);
    final Result<void> result;
    if (_enabled) {
      result = await controller.enable(
        interval: _interval,
        recipientContactIds: _selectedIds.toList(),
      );
    } else {
      result = await controller.disable();
    }
    final text = result.fold(
      (_) => _enabled ? 'Check-in started.' : 'Check-in turned off.',
      (failure) => failure.message,
    );
    messenger.showSnackBar(SnackBar(content: Text(text)));
    // Re-seed from the persisted document so the form reflects reality.
    _seeded = false;
  }
}

/// Live status of an active check-in cadence.
///
/// Honest labels only: "waiting for you to send" is distinct from any claim
/// that a message was delivered, because delivery is always user-mediated.
class _CheckInStatusCard extends StatelessWidget {
  const _CheckInStatusCard({required this.settings});

  final CheckInSettings settings;

  String? _format(DateTime? utc) {
    if (utc == null) return null;
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      (
        'Every',
        switch (settings.interval) {
          CheckInInterval.minutes60 => '60 min',
          CheckInInterval.minutes120 => '2 h',
          CheckInInterval.minutes180 => '3 h',
          CheckInInterval.devTest2 => '2 min',
        },
      ),
      (
        'Recipients',
        settings.recipientContactIds.length.toString(),
      ),
      ('Last attempt', _format(settings.lastAttemptAt) ?? '—'),
      (
        'Last location captured',
        _format(settings.lastSuccessfulLocationAt) ?? 'Never',
      ),
      ('Next check-in', _format(settings.nextScheduledAt) ?? '—'),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('ACTIVE', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    Text(value, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            if (settings.lastExecutionStatus != null &&
                settings.lastExecutionStatus !=
                    CheckInExecutionStatus.disabled) ...[
              const SizedBox(height: 8),
              Text(
                settings.lastExecutionStatus!.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}