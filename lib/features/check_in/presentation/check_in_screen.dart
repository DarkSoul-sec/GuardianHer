import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../application/check_in_providers.dart';
import '../application/check_in_state.dart';

/// Safety Check-In response screen.
///
/// Shown when a scheduled check-in reminder is tapped and reachable from
/// Settings. In the due state it offers the single "I'm safe" confirm action,
/// which captures a one-shot location and hands the message to the
/// user-confirmed sender. Honest by design: a missed-check-in banner and any
/// delivery failure are shown plainly, and a location failure never blocks the
/// check-in.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  bool _ranDueExecution = false;

  @override
  void initState() {
    super.initState();
    // Re-evaluate due/missed state when the screen opens (a missed check-in
    // escalates even if the app was closed when the reminder fired).
    Future.microtask(
      () => ref.read(checkInControllerProvider.notifier).refresh(),
    );
  }

  void _runDueExecutionIfNeeded(CheckInState state) {
    // A fired execution notification (or an already-due cadence) opens this
    // screen; complete the scheduled run HERE, in the foreground, where
    // location access and composer handoff are actually permitted. Runs once
    // per screen entry — afterwards the normal due/acknowledge UI takes over.
    if (_ranDueExecution ||
        !state.loaded ||
        !state.settings.enabled) {
      return;
    }
    final next = state.settings.nextScheduledAt;
    final lastAttempt = state.settings.lastAttemptAt;
    final isDue = next != null && !next.isAfter(DateTime.now().toUtc());
    final justFired =
        lastAttempt == null || !lastAttempt.isBefore(next ?? lastAttempt);
    if (!isDue && !justFired) {
      return;
    }
    _ranDueExecution = true;
    Future.microtask(
      () => ref.read(checkInControllerProvider.notifier).runDueCheckIn(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkInControllerProvider);
    _runDueExecutionIfNeeded(state);

    return Scaffold(
      appBar: AppBar(title: const Text('Safety check-in')),
      body: SafeArea(
        child: switch ((state.loaded, state.settings.enabled)) {
          (false, _) => const Center(child: CircularProgressIndicator()),
          (_, false) => _DisabledView(
              onOpenSettings: () => context.push(AppRoutes.checkInSettings),
            ),
          (_, true) => _CheckInReadyView(state: state),
        },
      ),
    );
  }
}

class _DisabledView extends StatelessWidget {
  const _DisabledView({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

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
              Icons.notifications_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Safety check-in is off',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Turn it on in Settings to receive a reminder at your chosen '
              'interval and send your trusted contacts a check-in message.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Check-in settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckInReadyView extends ConsumerWidget {
  const _CheckInReadyView({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = state.settings;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          state.isDue ? Icons.notifications_active_outlined : Icons.check_circle_outline,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          state.isDue ? 'Check-in due' : 'You are all caught up',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          state.isDue
              ? 'Confirm you are safe to send your check-in message to '
                  '${settings.recipientContactIds.length} '
                  '${settings.recipientContactIds.length == 1 ? 'person' : 'people'}.'
              : 'Your next check-in is scheduled. Confirm any time to send a '
                  'check-in message.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (state.missedCount > 0) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                state.missedCount == 1
                    ? 'You missed the previous check-in. Your next message '
                        'will say so.'
                    : 'You missed ${state.missedCount} check-ins. Your next '
                        'message will say so.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        if (state.statusMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            state.statusMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: state.isWorking
              ? null
              : () => _confirm(context, ref),
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('I am safe'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.push(AppRoutes.checkInSettings),
          child: const Text('Check-in settings'),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(checkInControllerProvider.notifier).acknowledge();
    final text = result.fold(
      (_) => 'Check-in message opened for sending.',
      (failure) => failure.message,
    );
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}