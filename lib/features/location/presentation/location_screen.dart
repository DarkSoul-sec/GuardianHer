import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../application/location_providers.dart';
import '../application/location_state.dart';
import '../domain/location_format.dart';
import '../domain/location_point.dart';
import 'whatsapp_share_flow.dart';

/// Current location capability.
///
/// One-shot only: the user asks for a single fix and the app shows it honestly,
/// including the platform-reported accuracy. Location is requested only when
/// the user taps "Get Current Location" (a short explanation is shown first),
/// never at app startup.
class LocationScreen extends ConsumerWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: SafeArea(
        child: switch (state.status) {
          LocationStatus.idle => _LocationIdleView(
              onGetLocation: () => _startCapture(context, ref),
            ),
          LocationStatus.loading => const _LocationLoadingView(),
          LocationStatus.captured => _LocationCapturedView(
              point: state.point!,
              onOpenInMaps: () => _openInMaps(context, ref),
              onShare: () => _share(context, ref),
              onWhatsApp: () =>
                  showWhatsAppShareFlow(context, ref, state.point!),
            ),
          LocationStatus.denied ||
          LocationStatus.servicesDisabled ||
          LocationStatus.timeout ||
          LocationStatus.unavailable =>
            _LocationErrorView(
              message: state.message ?? 'Location unavailable.',
              canRetry: state.canRetry,
              openSettings: state.openSettings,
              openLocationSettings: state.openLocationSettings,
              onRetry: () => _startCapture(context, ref),
              onOpenSettings: () =>
                  ref.read(locationControllerProvider.notifier).openSettings(),
              onOpenLocationSettings: () => ref
                  .read(locationControllerProvider.notifier)
                  .openLocationSettings(),
            ),
        },
      ),
    );
  }

  /// Shows the contextual permission explanation before requesting access, so
  /// the system permission dialog only ever follows an informed user action.
  Future<void> _startCapture(BuildContext context, WidgetRef ref) async {
    final status =
        await ref.read(permissionServiceProvider).status(AppPermission.location);
    if (status == PermissionStatus.denied) {
      if (!context.mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow location access?'),
          content: const Text(
            'GuardianHer needs your location to show where you are and help '
            'you share it during an emergency.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await ref.read(locationControllerProvider.notifier).captureLocation();
  }

  Future<void> _openInMaps(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(locationControllerProvider.notifier).openInMaps();
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(locationControllerProvider.notifier).shareLocation();
    if (result case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _LocationIdleView extends StatelessWidget {
  const _LocationIdleView({required this.onGetLocation});

  final VoidCallback onGetLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.my_location_outlined,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('My Location', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Get your current location once and share it when you choose.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onGetLocation,
              icon: const Icon(Icons.location_searching_outlined),
              label: const Text('Get Current Location'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationLoadingView extends StatelessWidget {
  const _LocationLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Getting your location…', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _LocationCapturedView extends StatelessWidget {
  const _LocationCapturedView({
    required this.point,
    required this.onOpenInMaps,
    required this.onShare,
    required this.onWhatsApp,
  });

  final LocationPoint point;
  final VoidCallback onOpenInMaps;
  final VoidCallback onShare;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latitude = point.latitude.toStringAsFixed(6);
    final longitude = point.longitude.toStringAsFixed(6);
    final accuracy = formatAccuracy(point.accuracyMeters);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on_outlined,
                size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            // Stale fixes are always labeled as last known — never presented
            // as a current capture.
            Text(
              point.isStale ? 'Last known location' : 'Location captured',
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _ValueRow(label: 'Latitude', value: latitude),
                const Divider(),
                _ValueRow(label: 'Longitude', value: longitude),
                const Divider(),
                _ValueRow(label: 'Accuracy', value: accuracy),
                const Divider(),
                _ValueRow(
                  label: 'Captured',
                  value: formatCapturedTime(point.capturedAt),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: onOpenInMaps,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Open in Maps'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share Location'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 12),
        // Direct WhatsApp targeting (Phase 3I): one tap, one contact, one
        // launch attempt. The number is canonicalized for the deep link and a
        // graceful fallback dialog appears when WhatsApp cannot be opened.
        OutlinedButton.icon(
          onPressed: onWhatsApp,
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Send via WhatsApp'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _LocationErrorView extends StatelessWidget {
  const _LocationErrorView({
    required this.message,
    required this.canRetry,
    required this.openSettings,
    required this.openLocationSettings,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onOpenLocationSettings,
  });

  final String message;
  final bool canRetry;
  final bool openSettings;
  final bool openLocationSettings;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off_outlined,
                size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 32),
            if (canRetry)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
              ),
            if (openLocationSettings) ...[
              if (canRetry) const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onOpenLocationSettings,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Turn on location'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
              ),
            ],
            if (openSettings) ...[
              if (canRetry || openLocationSettings) const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open Settings'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}