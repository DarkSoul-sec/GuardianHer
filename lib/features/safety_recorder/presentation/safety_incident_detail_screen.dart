import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/premium_components.dart';
import '../../../features/journey/domain/safety_recorder_events.dart';
import '../application/safety_recorder_controller.dart';
import '../domain/safety_incident.dart';

/// Detail screen for a single safety incident.
///
/// Shows the event timeline with timestamps and integrity status.
/// Vehicle information is displayed if present.
class SafetyIncidentDetailScreen extends ConsumerWidget {
  const SafetyIncidentDetailScreen({
    super.key,
    required this.incident,
  });

  final SafetyIncident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verified = incident.verifyIntegrity();

    return Scaffold(
      backgroundColor: AppTheme.navyBase,
      appBar: AppBar(
        title: const Text('Incident Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (!incident.isActive)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.sosRed),
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, verified),
            const SizedBox(height: 24),
            if (incident.vehicleType != null) ...[
              _buildVehicleSection(context),
              const SizedBox(height: 24),
            ],
            _buildIntegritySection(context, verified),
            const SizedBox(height: 24),
            _buildTimelineSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool verified) {
    final statusColor = incident.isActive
        ? AppTheme.sosRed
        : (verified ? AppTheme.successGreen : AppTheme.warningAmber);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _formatDateTime(incident.createdAt),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (incident.endedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ended: ${_formatDateTime(incident.endedAt!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _StatChip(
                label: '${incident.events.length}',
                subtitle: 'events',
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: incident.isActive ? 'Active' : 'Completed',
                subtitle: 'status',
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: verified ? 'Yes' : 'No',
                subtitle: 'verified',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_car, color: AppTheme.violetLight, size: 20),
              const SizedBox(width: 8),
              Text(
                'Vehicle Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Type: ${incident.vehicleType!.label}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          if (incident.hasVehicleRegistration) ...[
            const SizedBox(height: 4),
            Text(
              'Registration recorded (redacted)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textLavender,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntegritySection(BuildContext context, bool verified) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                verified ? Icons.verified_outlined : Icons.warning_amber_outlined,
                color: verified ? AppTheme.successGreen : AppTheme.warningAmber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Integrity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verified
                ? 'The event chain is intact and tamper-evident. All hashes match from genesis to the final event.'
                : 'Integrity could not be verified. The event chain may be incomplete.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Genesis: ${incident.genesisHash.substring(0, 16)}…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textMuted,
              fontFamily: 'monospace',
            ),
          ),
          if (incident.hashes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Chain length: ${incident.hashes.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Timeline',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...incident.events.asMap().entries.map((entry) {
          final index = entry.key;
          final event = entry.value;
          final isLast = index == incident.events.length - 1;
          return _TimelineEvent(
            event: event,
            isLast: isLast,
          );
        }),
      ],
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.navyElevated,
        title: const Text(
          'Delete Incident',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'This incident will be permanently deleted. This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(safetyRecorderProvider.notifier).deleteIncident(incident.id);
              Navigator.of(context).pop();
              context.pop();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.sosRed),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.glassFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.glassBorder.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({required this.event, required this.isLast});

  final RecordedSafetyEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final category = categoryForEventType(event.eventType);
    final color = _colorForCategory(category);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: AppTheme.glassBorder.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventTypeLabel(event.eventType),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(event.occurredAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForCategory(SafetyEventCategory category) {
    return switch (category) {
      SafetyEventCategory.sos => AppTheme.sosRed,
      SafetyEventCategory.journey => AppTheme.violetLight,
      SafetyEventCategory.location => AppTheme.infoCyan,
      SafetyEventCategory.communication => AppTheme.magenta,
      SafetyEventCategory.session => AppTheme.successGreen,
      SafetyEventCategory.checkIn => AppTheme.warningAmber,
    };
  }

  String _eventTypeLabel(SafetyEventType type) {
    return switch (type) {
      SafetyEventType.sessionStarted => 'Session started',
      SafetyEventType.sessionCompleted => 'Session completed',
      SafetyEventType.sessionExpired => 'Session expired',
      SafetyEventType.vehicleAttached => 'Vehicle attached',
      SafetyEventType.journeyStarted => 'Journey started',
      SafetyEventType.journeyEnded => 'Journey ended',
      SafetyEventType.sosActivated => 'SOS activated',
      SafetyEventType.sosCancellationStarted => 'SOS cancellation started',
      SafetyEventType.sosCompleted => 'SOS completed',
      SafetyEventType.locationCaptureStarted => 'Location capture started',
      SafetyEventType.locationCaptured => 'Location captured',
      SafetyEventType.locationUnavailable => 'Location unavailable',
      SafetyEventType.locationTimeout => 'Location timeout',
      SafetyEventType.locationPermissionDenied => 'Location permission denied',
      SafetyEventType.locationServicesDisabled => 'Location services disabled',
      SafetyEventType.locationUpdated => 'Location updated',
      SafetyEventType.communicationAttempted => 'Communication attempted',
      SafetyEventType.communicationFailed => 'Communication failed',
      SafetyEventType.communicationHandedOff => 'Communication handed off',
      SafetyEventType.shakeDetected => 'Shake detected',
      SafetyEventType.checkInStarted => 'Check-in started',
      SafetyEventType.checkInCompleted => 'Check-in completed',
    };
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
