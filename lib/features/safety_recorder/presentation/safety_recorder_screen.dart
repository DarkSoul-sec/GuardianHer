import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/router/app_router.dart';
import '../../../shared/widgets/premium_components.dart';
import '../application/safety_recorder_controller.dart';
import '../domain/safety_incident.dart';

/// Safety Incidents timeline screen.
///
/// Shows a list of completed safety incidents with integrity status.
/// Accessible from the Activity tab or Settings > Privacy.
class SafetyRecorderScreen extends ConsumerWidget {
  const SafetyRecorderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorderState = ref.watch(safetyRecorderProvider);
    final incidents = recorderState.recentIncidents;
    final currentIncident = recorderState.currentIncident;

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: const Text('Safety Incidents'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
      ),
      body: incidents.isEmpty && currentIncident == null
          ? _buildEmptyState(context)
          : _buildIncidentList(context, ref, incidents, currentIncident),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.guardianIndigo.withValues(alpha: 0.15),
              border: Border.all(
                color: AppTheme.guardianIndigo.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 40,
              color: AppTheme.guardianIndigo,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Safety Incidents',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.guardianIndigo,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Incidents are recorded automatically during\nSOS activations and safety sessions.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textBody,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentList(
    BuildContext context,
    WidgetRef ref,
    List<SafetyIncident> incidents,
    SafetyIncident? currentIncident,
  ) {
    return CustomScrollView(
      slivers: [
        if (currentIncident != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: PremiumSectionHeader(
                title: 'Recording',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _IncidentCard(
                incident: currentIncident,
                isActive: true,
                onTap: () => context.push(
                  AppRoutes.safetyIncidentDetail,
                  extra: currentIncident,
                ),
              ),
            ),
          ),
        ],
        if (incidents.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: PremiumSectionHeader(
                title: 'Completed',
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList.builder(
              itemCount: incidents.length,
              itemBuilder: (context, index) {
                final incident = incidents[index];
                return _IncidentCard(
                  incident: incident,
                  isActive: false,
                  onTap: () => context.push(
                    AppRoutes.safetyIncidentDetail,
                    extra: incident,
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.isActive,
    required this.onTap,
  });

  final SafetyIncident incident;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          child: Row(
            children: [
              _buildStatusIcon(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(incident.createdAt),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.guardianIndigo,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${incident.events.length} event${incident.events.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textBody,
                      ),
                    ),
                    if (incident.vehicleType != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Vehicle: ${incident.vehicleType!.label}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textBody,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _buildIntegrityBadge(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    final color = isActive ? AppTheme.sosCoral : AppTheme.successGreen;
    final icon = isActive ? Icons.circle : Icons.check_circle;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(icon, size: 24, color: color),
    );
  }

  Widget _buildIntegrityBadge(BuildContext context) {
    if (isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.sosCoral.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Recording',
          style: TextStyle(
            color: AppTheme.sosCoral,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final verified = incident.verifyIntegrity();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (verified ? AppTheme.successGreen : AppTheme.warningAmber)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        verified ? 'Verified' : 'Unverified',
        style: TextStyle(
          color: verified ? AppTheme.successGreen : AppTheme.warningAmber,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}
