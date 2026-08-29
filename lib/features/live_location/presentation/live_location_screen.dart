import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/providers.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/application/contacts_state.dart';
import '../../contacts/domain/phone_number.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../application/live_location_providers.dart';
import '../domain/live_location_session.dart';
import '../domain/live_share_message.dart';

/// "Share Live Location" screen (Phase 3J §17).
///
/// Idle → pick a duration → start. Active → LIVE badge, remaining time,
/// last update, connection state, STOP, and the share row (WhatsApp / SMS /
/// Share / Copy link). All sending is user-confirmed; nothing is automatic.
class LiveLocationScreen extends ConsumerStatefulWidget {
  const LiveLocationScreen({super.key});

  @override
  ConsumerState<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends ConsumerState<LiveLocationScreen> {
  LiveShareDuration _selected = LiveShareDuration.minutes30;

  @override
  void initState() {
    super.initState();
    // Re-evaluate expiry when the user returns to this screen (§7).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveLocationControllerProvider.notifier).refresh();
    });
  }

  Future<void> _start() async {
    await ref.read(liveLocationControllerProvider.notifier).start(_selected);
  }

  Future<void> _confirmStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
          'Your live location link stops working immediately and your last '
          'location is removed from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(liveLocationControllerProvider.notifier).stopSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live location sharing stopped.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveLocationControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Live location')),
      body: SafeArea(
        child: switch (state.status) {
          LiveSessionStatus.idle ||
          LiveSessionStatus.stopped ||
          LiveSessionStatus.expired ||
          LiveSessionStatus.failed =>
            _IdleView(
              selected: _selected,
              onSelect: (d) => setState(() => _selected = d),
              onStart: _start,
              noticeKey: state.failure?.key,
            ),
          LiveSessionStatus.starting => const _CenteredProgress(
              label: 'Starting live location…',
            ),
          LiveSessionStatus.stopping => const _CenteredProgress(
              label: 'Stopping…',
            ),
          LiveSessionStatus.active => _ActiveView(onStop: _confirmStop),
        },
      ),
    );
  }
}

/// Duration picker + privacy explainer for the dormant state.
class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.selected,
    required this.onSelect,
    required this.onStart,
    this.noticeKey,
  });

  final LiveShareDuration selected;
  final ValueChanged<LiveShareDuration> onSelect;
  final VoidCallback onStart;
  final String? noticeKey;

  static const _notices = <String, String>{
    'stoppedByUser': 'Sharing stopped.',
    'expired': 'The previous session expired.',
    'failedPermission':
        'Location permission is needed to share live location.',
    'failedNotConfigured':
        'Live sharing is not available in this build.',
    'failedServicesDisabled': 'Turn on location services to share.',
  };

  @override
  Widget build(BuildContext context) {
    final notice = noticeKey == null ? null : _notices[noticeKey];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (notice != null) ...[
          Text(notice, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
        ],
        Text(
          'Share where you are with someone you trust for a limited time. '
          'They open a secure link in any browser — no app or account needed.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Text('Share for', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final duration in LiveShareDuration.values)
              ChoiceChip(
                label: Text('${duration.minutes} min'),
                selected: duration == selected,
                onSelected: (_) => onSelect(duration),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.share_location),
          label: const Text('Start sharing'),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('A notification stays while sharing'),
          subtitle: const Text(
            'You can always stop from here; the link also expires on its own.',
          ),
        ),
      ],
    );
  }
}

/// The active session dashboard.
class _ActiveView extends ConsumerWidget {
  const _ActiveView({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveLocationControllerProvider);
    final session = state.session!;
    final remaining = session.remainingTime;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration:
                  const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'LIVE',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '$minutes:${seconds.toString().padLeft(2, '0')} left',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const Divider(height: 28),
        _InfoLine(
          icon: Icons.update,
          label: session.lastLocationAt == null
              ? 'Waiting for the first location fix…'
              : 'Last updated: ${_relativeAge(session.lastLocationAt!)}',
        ),
        _InfoLine(
          icon: state.connectionUp
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          label: state.connectionUp
              ? 'Location is being shared'
              : 'Connection unavailable — capture continues, '
                  'sharing resumes automatically',
        ),
        if (!state.connectionUp)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Connection unavailable — your location will be shared again '
              'when the network returns.',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop sharing'),
        ),
        const SizedBox(height: 24),
        if (session.shareUrl.isEmpty)
          const ListTile(
            leading: Icon(Icons.link_off),
            title: Text('Link will appear once the connection is back.'),
          )
        else ...[
          Text('Share the link', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _ShareRow(session: session),
        ],
      ],
    );
  }

  static String _relativeAge(DateTime capturedAt) {
    final age = DateTime.now().toUtc().difference(capturedAt.toUtc());
    if (age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    return '${age.inHours} h ago';
  }
}

class _ShareRow extends ConsumerWidget {
  const _ShareRow({required this.session});

  final LiveLocationSession session;

  void _reportFailure(BuildContext context, Object error) {
    final copy = error is Failure ? liveFailureCopy(error) : 'This action did '
        'not work. Try another way to share.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(copy)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = buildLiveShareMessage(
      shareUrl: session.shareUrl,
      expiresAt: session.expiresAt,
    );

    Future<void> openWhatsApp() async {
      final contact = await _pickContact(context, ref);
      if (contact == null || !context.mounted) return;
      final result = await ref.read(whatsappServiceProvider).openChat(
            phoneNumber: contact.phoneNumber,
            body: message,
          );
      if (context.mounted && result.isErr) {
        _showWhatsAppFallback(context, ref, contact.phoneNumber, message);
      }
    }

    Future<void> openSms() async {
      final contact = await _pickContact(context, ref);
      if (contact == null || !context.mounted) return;
      final result = await ref.read(smsServiceProvider).openComposer(
            phoneNumber: PhoneNumber.normalize(contact.phoneNumber),
            body: message,
          );
      if (context.mounted && result.isErr) {
        _reportFailure(context, result.fold((_) => null, (f) => f)!);
      }
    }

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: session.shareUrl));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied.')),
        );
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: openWhatsApp,
          icon: const Icon(Icons.chat_outlined),
          label: const Text('WhatsApp'),
        ),
        OutlinedButton.icon(
          onPressed: openSms,
          icon: const Icon(Icons.sms_outlined),
          label: const Text('SMS'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final result =
                await ref.read(shareServiceProvider).shareText(message);
            if (context.mounted && result.isErr) {
              _reportFailure(context, result.fold((_) => null, (f) => f)!);
            }
          },
          icon: const Icon(Icons.ios_share),
          label: const Text('Share'),
        ),
        OutlinedButton.icon(
          onPressed: copy,
          icon: const Icon(Icons.copy),
          label: const Text('Copy link'),
        ),
      ],
    );
  }

  Future<TrustedContact?> _pickContact(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(contactsControllerProvider);
    final contacts = switch (state) {
      ContactsLoaded(:final contacts) => contacts,
      _ => <TrustedContact>[],
    };
    if (contacts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a trusted contact first.')),
        );
      }
      return null;
    }
    if (contacts.length == 1 || !context.mounted) {
      return contacts.first;
    }
    return showModalBottomSheet<TrustedContact>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final contact in contacts)
              ListTile(
                title: Text(contact.name),
                subtitle: const Text('Trusted contact'),
                onTap: () => Navigator.of(sheetContext).pop(contact),
              ),
          ],
        ),
      ),
    );
  }

  void _showWhatsAppFallback(
    BuildContext context,
    WidgetRef ref,
    String phoneNumber,
    String message,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("WhatsApp isn't available for this contact."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(smsServiceProvider).openComposer(
                    phoneNumber: PhoneNumber.normalize(phoneNumber),
                    body: message,
                  );
            },
            child: const Text('Send via SMS'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(shareServiceProvider).shareText(message);
            },
            child: const Text('Share another way'),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _CenteredProgress extends StatelessWidget {
  const _CenteredProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}
