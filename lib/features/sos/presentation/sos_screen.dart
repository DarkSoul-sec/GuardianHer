import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/platform/live_sharing_service.dart';
import '../../../shared/widgets/premium_components.dart';
import '../../../app/theme/app_theme.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/application/contacts_state.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../../journey/application/emergency_vehicle_context.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../location/domain/location_share_message.dart';
import '../application/emergency_orchestrator.dart';
import '../application/sos_actions_state.dart';
import '../application/sos_providers.dart';
import '../application/sos_state.dart';

/// SOS emergency workflow.
///
/// Premium dark-mode emergency interface with high contrast for outdoor /
/// under-stress readability. All existing text finders are preserved for test
/// compatibility.
class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sosControllerProvider);
    ref.watch(sosActionsControllerProvider);

    return Scaffold(
      backgroundColor: AppTheme.navyBase,
      body: SafeArea(
        child: switch (state) {
          SosIdle() => _SosIdleView(
              onStart: () =>
                  ref.read(sosControllerProvider.notifier).startSos(),
            ),
          SosCountdown() => const _SosActivatingView(),
          SosActive() => _SosActiveView(
              onEnd: () =>
                  ref.read(sosControllerProvider.notifier).cancelSos(),
            ),
          SosCancelling() => const _SosCancellingView(),
          SosCompleted() => _SosCompletedView(
              onDismiss: () =>
                  ref.read(sosControllerProvider.notifier).resetSos(),
            ),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Idle: arm SOS
// ─────────────────────────────────────────────────────────────────────────────

class _SosIdleView extends StatelessWidget {
  const _SosIdleView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AmbientBackground(
      centerGlowColor: AppTheme.sosRed,
      centerGlowRadius: 180,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined,
                  size: 56, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Emergency SOS',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Press SOS and the emergency workflow starts immediately — '
                'nothing is delayed.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(160, 160),
                  shape: const CircleBorder(),
                  backgroundColor: AppTheme.sosRed,
                  foregroundColor: Colors.white,
                  textStyle: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: Semantics(
                  label: 'Start SOS',
                  button: true,
                  child: const Text('SOS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown / Activating
// ─────────────────────────────────────────────────────────────────────────────

class _SosActivatingView extends StatelessWidget {
  const _SosActivatingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: AppTheme.sosRed,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Activating SOS…',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active emergency
// ─────────────────────────────────────────────────────────────────────────────

class _SosActiveView extends ConsumerWidget {
  const _SosActiveView({required this.onEnd});

  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = ref.watch(sosActionsControllerProvider);
    final contacts = ref.watch(contactsControllerProvider);
    final emergency = ref.watch(emergencyOrchestratorProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2D0A12),
            AppTheme.navyBase,
          ],
          stops: [0.0, 0.3],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Active status banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.sosRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.sosRed.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.sosRed,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.sosRed.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'SOS ACTIVE',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.sosRed,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Emergency SMS are being sent to your guardians automatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _StatusLine(fragments: actions.statusFragments),
            if (emergency.incidentId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Incident: ${emergency.incidentId!.substring(0, 8)}…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const _EmergencyVehicleSection(),
            const _SosLocationSection(),
            const _LiveSharingSection(),
            if (emergency.phase == EmergencyPhase.active &&
                (emergency.guardians.isNotEmpty ||
                    emergency.errorMessage != null))
              _EmergencySmsSection(emergency: emergency),
            const SizedBox(height: 8),
            Expanded(
              child: _ContactsSection(
                state: contacts,
                onCall: (contact) =>
                    _runAction(context, ref, () => ref
                        .read(sosActionsControllerProvider.notifier)
                        .callContact(contact)),
                onMessage: (contact) =>
                    _runAction(context, ref, () => ref
                        .read(sosActionsControllerProvider.notifier)
                        .messageContact(contact)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _runAction(
                context,
                ref,
                () => ref
                    .read(sosActionsControllerProvider.notifier)
                    .callEmergency(),
              ),
              icon: const Icon(Icons.local_phone),
              label: const Text('Call emergency'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onEnd,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('End SOS'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppTheme.sosRed,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Future<Result<SosActionOutcome>> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action();
    final text =
        result.fold((outcome) => outcome.message, (failure) => failure.message);
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status line fragments
// ─────────────────────────────────────────────────────────────────────────────

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.fragments});

  final List<String> fragments;

  @override
  Widget build(BuildContext context) {
    if (fragments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        fragments.join(' · '),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textMuted,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Emergency vehicle section (Phase D)
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencyVehicleSection extends ConsumerWidget {
  const _EmergencyVehicleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(emergencyVehicleContextProvider);
    if (vehicle == null) return const SizedBox.shrink();
    final reg = vehicle.displayRegistrationNumber;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              'Vehicle: ${vehicle.type.label}',
              style: const TextStyle(
                color: AppTheme.textLavender,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (reg != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SelectableText(
                  reg,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location section — 7 truthful states (Phase 3I)
// ─────────────────────────────────────────────────────────────────────────────

class _SosLocationSection extends ConsumerWidget {
  const _SosLocationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);
    if (location.status == LocationStatus.idle) {
      return const SizedBox.shrink();
    }
    final point = location.point;
    final primary = location.statusLabel;
    final secondary = location.statusDetail;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (location.status == LocationStatus.loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.violetLight,
                  ),
                )
              else
                Icon(
                  _statusIcon(location),
                  size: 16,
                  color: AppTheme.textMuted,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  primary ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
              ),
            ],
          ),
          if (secondary != null) ...[
            const SizedBox(height: 2),
            Text(
              secondary,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
            ),
          ],
          if (location.status == LocationStatus.captured && point != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () =>
                  ref.read(locationControllerProvider.notifier).openInMaps(),
              child: Text(
                'Location: ${buildMapsShareUrl(point)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.violetLight,
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ],
          ..._recoveryActions(context, ref, location),
        ],
      ),
    );
  }

  IconData _statusIcon(LocationState location) => switch (location.status) {
        LocationStatus.captured when location.point?.isStale == true =>
          Icons.history_outlined,
        LocationStatus.captured => Icons.location_on_outlined,
        LocationStatus.timeout ||
        LocationStatus.unavailable ||
        LocationStatus.denied ||
        LocationStatus.servicesDisabled =>
          Icons.location_off_outlined,
        LocationStatus.loading || LocationStatus.idle =>
          Icons.location_on_outlined,
      };

  List<Widget> _recoveryActions(
    BuildContext context,
    WidgetRef ref,
    LocationState location,
  ) {
    final actions = <Widget>[];
    void add(String label, IconData icon, VoidCallback onPressed) {
      actions.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              textStyle: Theme.of(context).textTheme.labelLarge,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ),
      );
    }

    switch (location.status) {
      case LocationStatus.servicesDisabled:
        add(
          'Turn on location',
          Icons.location_on_outlined,
          () => ref
              .read(locationControllerProvider.notifier)
              .openLocationSettings(),
        );
      case LocationStatus.denied:
        add(
          'Open Settings',
          Icons.settings_outlined,
          () => ref.read(locationControllerProvider.notifier).openSettings(),
        );
      case LocationStatus.timeout || LocationStatus.unavailable:
        if (location.canRetry) {
          add(
            'Try again',
            Icons.refresh,
            () => ref
                .read(locationControllerProvider.notifier)
                .captureLocation(),
          );
        }
      case LocationStatus.idle ||
            LocationStatus.loading ||
            LocationStatus.captured:
        break;
    }
    return actions;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live sharing via SMS relay (serverless)
// ─────────────────────────────────────────────────────────────────────────────

class _LiveSharingSection extends ConsumerWidget {
  const _LiveSharingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosState = ref.watch(sosControllerProvider);
    final actions = ref.watch(sosActionsControllerProvider);

    // Show indicator when SOS is active (live sharing runs during SOS)
    if (sosState is! SosActive) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.violet.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.violet.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.violet,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.violet.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'LIVE SHARING ACTIVE',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.violet,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'SMS location updates sent every 30s to guardians',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap link in SMS to track in Maps',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trusted contacts with call / message
// ─────────────────────────────────────────────────────────────────────────────

class _ContactsSection extends ConsumerWidget {
  const _ContactsSection({
    required this.state,
    required this.onCall,
    required this.onMessage,
  });

  final ContactsState state;
  final void Function(TrustedContact contact) onCall;
  final void Function(TrustedContact contact) onMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = switch (state) {
      ContactsLoaded(:final contacts) => contacts,
      _ => const <TrustedContact>[],
    };

    if (contacts.isEmpty) {
      return Center(
        child: Text(
          'No trusted contacts yet. Add them in the Contacts tab to call or '
          'message them from here.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
      );
    }

    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.violet.withValues(alpha: 0.2),
                child: Text(
                  contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppTheme.violetLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _maskPhone(contact.phoneNumber),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Call ${contact.name}',
                onPressed: () => onCall(contact),
                icon: const Icon(Icons.call, color: AppTheme.successGreen),
              ),
              IconButton(
                tooltip: 'Message ${contact.name}',
                onPressed: () => onMessage(contact),
                icon: const Icon(Icons.message_outlined,
                    color: AppTheme.violetLight),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _maskPhone(String digits) {
  if (digits.length <= 4) return digits;
  final tail = digits.substring(digits.length - 4);
  return '${List.filled(digits.length - 4, '•').join()}$tail';
}

// ─────────────────────────────────────────────────────────────────────────────
// Emergency SMS section — automatic guardian delivery status
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencySmsSection extends StatelessWidget {
  const _EmergencySmsSection({required this.emergency});

  final EmergencyOrchestratorState emergency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sms_outlined,
                  size: 16,
                  color: emergency.errorMessage != null
                      ? AppTheme.sosRed
                      : AppTheme.violetLight,
                ),
                const SizedBox(width: 6),
                Text(
                  'Emergency SMS',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (emergency.batteryPercentage != null)
                  Text(
                    '🔋 ${emergency.batteryPercentage}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
            if (emergency.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                emergency.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.sosRed,
                ),
              ),
            ],
            if (emergency.locationStatusMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                emergency.locationStatusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
            ],
            for (final guardian in emergency.guardians)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    _deliveryIcon(guardian.status),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        guardian.contactName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    _deliveryLabel(guardian.status, theme),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _deliveryIcon(GuardianDeliveryStatus status) {
    return switch (status) {
      GuardianDeliveryStatus.pending => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.textMuted,
          ),
        ),
      GuardianDeliveryStatus.sending => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.violetLight,
          ),
        ),
      GuardianDeliveryStatus.sent => const Icon(
          Icons.check_circle_outline,
          size: 16,
          color: AppTheme.successGreen,
        ),
      GuardianDeliveryStatus.failed => const Icon(
          Icons.error_outline,
          size: 16,
          color: AppTheme.sosRed,
        ),
      GuardianDeliveryStatus.retrying => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.sosRed.withValues(alpha: 0.7),
          ),
        ),
    };
  }

  Widget _deliveryLabel(GuardianDeliveryStatus status, ThemeData theme) {
    final text = switch (status) {
      GuardianDeliveryStatus.pending => 'Pending',
      GuardianDeliveryStatus.sending => 'Sending…',
      GuardianDeliveryStatus.sent => 'Sent',
      GuardianDeliveryStatus.failed => 'Failed',
      GuardianDeliveryStatus.retrying => 'Retrying…',
    };
    final color = switch (status) {
      GuardianDeliveryStatus.sent => AppTheme.successGreen,
      GuardianDeliveryStatus.failed => AppTheme.sosRed,
      _ => AppTheme.textMuted,
    };
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cancelling
// ─────────────────────────────────────────────────────────────────────────────

class _SosCancellingView extends StatelessWidget {
  const _SosCancellingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.sosRed,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Stopping SOS…',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Completed
// ─────────────────────────────────────────────────────────────────────────────

class _SosCompletedView extends StatelessWidget {
  const _SosCompletedView({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.successGreen.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.successGreen.withValues(alpha: 0.2),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 40,
                color: AppTheme.successGreen,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'SOS session ended',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Return to start a new session whenever you need help.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 36),
            FilledButton(
              onPressed: onDismiss,
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 48),
                backgroundColor: AppTheme.violet,
                foregroundColor: AppTheme.textPrimary,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}
