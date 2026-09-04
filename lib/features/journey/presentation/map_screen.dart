import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';
import '../../journey/application/journey_providers.dart';
import '../../journey/domain/journey_state.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';

/// Map tab — current location + journey status in the premium light system.
///
/// Reuses the existing location and journey infrastructure; no new tracking.
/// Full journey management stays on the existing Journey screen.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);
    final journey = ref.watch(journeyControllerProvider);

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Text(
          'Map',
          style: GoogleFonts.inter(
            color: AppTheme.guardianIndigo,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rounded map/status container
            GhCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: 260,
                  color: AppTheme.lavenderSoft.withValues(alpha: 0.4),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 72,
                        color: AppTheme.guardianIndigo.withValues(alpha: 0.3),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceWhite,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.softShadow(),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _locationIcon(location.status),
                                size: 18,
                                color: AppTheme.guardianIndigo,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  location.statusLabel ?? 'Location idle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.guardianIndigo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const GhSectionTitle(title: 'Journey'),
            _JourneyStatusCard(journey: journey),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.journey),
                    icon: const Icon(Icons.route_outlined, size: 20),
                    label: const Text('Open Journey'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.location),
                    icon: const Icon(Icons.my_location_outlined, size: 20),
                    label: const Text('My Location'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _locationIcon(LocationStatus status) => switch (status) {
        LocationStatus.captured => Icons.location_on,
        LocationStatus.loading => Icons.location_searching,
        _ => Icons.location_off_outlined,
      };
}

class _JourneyStatusCard extends StatelessWidget {
  const _JourneyStatusCard({required this.journey});

  final JourneyState journey;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = switch (journey) {
      JourneyIdle() => (
          'No active journey',
          'Start a Safe Journey to share your trip with trusted contacts.',
          Icons.route_outlined,
        ),
      JourneyStarting() => (
          'Starting journey…',
          'Preparing your safe journey.',
          Icons.hourglass_top_outlined,
        ),
      JourneyActive() => (
          'Journey running',
          'Your journey is active. Manage it from the Journey screen.',
          Icons.directions_car_outlined,
        ),
      JourneyCompleted(:final reason) => (
          'Last journey ended',
          reason == JourneyEndReason.escalatedToSos
              ? 'Handed over to emergency.'
              : 'You arrived safely.',
          Icons.flag_outlined,
        ),
    };
    return GhCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.lavenderSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppTheme.guardianIndigo, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.guardianIndigo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textBody,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
