import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/guardianher_design.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';

/// Map tab — honest current-location status using only the real location
/// infrastructure. No decorative map, no journey UI, no tracking claims.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);

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
            GhCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.lavenderSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _locationIcon(location.status),
                          color: AppTheme.guardianIndigo,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current location',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textFaint,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              location.statusLabel ?? 'Location idle',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.guardianIndigo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (location.statusDetail != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      location.statusDetail!,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textBody,
                      ),
                    ),
                  ],
                  if (location.status == LocationStatus.captured &&
                      location.point != null) ...[
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: Icons.my_location_outlined,
                      text:
                          'Accuracy ±${location.point!.accuracyMeters.toStringAsFixed(0)} m',
                    ),
                    const SizedBox(height: 8),
                    _DetailRow(
                      icon: Icons.access_time_outlined,
                      text:
                          'Captured ${_formatTime(location.point!.capturedAt)}',
                    ),
                  ],
                  ..._recoveryAction(context, ref, location),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.location),
              icon: const Icon(Icons.my_location_outlined, size: 20),
              label: const Text('My Location'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your location is captured only when you ask for it — for SOS, '
              'check-ins, or sharing — and never tracked continuously.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _recoveryAction(
    BuildContext context,
    WidgetRef ref,
    LocationState location,
  ) {
    switch (location.status) {
      case LocationStatus.servicesDisabled:
        return [
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref
                .read(locationControllerProvider.notifier)
                .openLocationSettings(),
            icon: const Icon(Icons.location_on_outlined, size: 20),
            label: const Text('Turn on location'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ];
      case LocationStatus.denied:
        return [
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(locationControllerProvider.notifier).openSettings(),
            icon: const Icon(Icons.settings_outlined, size: 20),
            label: const Text('Open Settings'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ];
      case LocationStatus.timeout:
      case LocationStatus.unavailable:
        if (!location.canRetry) return [];
        return [
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref
                .read(locationControllerProvider.notifier)
                .captureLocation(),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Try again'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ];
      case LocationStatus.idle:
      case LocationStatus.loading:
      case LocationStatus.captured:
        return [];
    }
  }

  IconData _locationIcon(LocationStatus status) => switch (status) {
        LocationStatus.captured => Icons.location_on,
        LocationStatus.loading => Icons.location_searching,
        _ => Icons.location_off_outlined,
      };

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textBody),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textBody,
            ),
          ),
        ),
      ],
    );
  }
}
