import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../location/domain/location_format.dart';
import '../application/journey_providers.dart';
import '../application/journey_share_message.dart';
import '../domain/vehicle_registration.dart';
import '../domain/journey_state.dart';

/// Safe Journey (Phases C/D): start (optionally recording the vehicle in
/// seconds) → travel with a shareable live link → arrive and end. A shake
/// SOS during the journey transforms it into the emergency flow — this
/// screen never fights that handover.
class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  final _registrationController = TextEditingController();
  final _driverController = TextEditingController();
  final _bookingController = TextEditingController();
  VehicleType _selectedType = VehicleType.taxi;
  String? _registrationError;
  String? _driverError;
  String? _bookingError;

  @override
  void initState() {
    super.initState();
    // Requirement M: a new journey never inherits the previous vehicle —
    // clear stale form input as soon as the last session's banner is gone.
    ref.listenManual(journeyControllerProvider, (previous, next) {
      if (previous is JourneyCompleted && next is JourneyIdle) {
        _resetForm();
      }
    });
  }

  void _resetForm() {
    if (!mounted) return;
    _registrationController.clear();
    _driverController.clear();
    _bookingController.clear();
    setState(() {
      _selectedType = VehicleType.taxi;
      _registrationError = null;
      _driverError = null;
      _bookingError = null;
    });
  }

  @override
  void dispose() {
    _registrationController.dispose();
    _driverController.dispose();
    _bookingController.dispose();
    super.dispose();
  }

  VehicleInfo? _vehicleFromForm() {
    setState(() {
      _registrationError = null;
      _driverError = null;
      _bookingError = null;
    });

    final driverRaw = _driverController.text.trim();
    const maxDriverLength = 60;
    if (driverRaw.length > maxDriverLength) {
      setState(() => _driverError = 'Driver name is too long.');
      return null;
    }
    final bookingRaw = _bookingController.text.trim();
    const maxBookingLength = 60;
    if (bookingRaw.length > maxBookingLength) {
      setState(() => _bookingError = 'Booking reference is too long.');
      return null;
    }

    final rawRegistration = _registrationController.text;
    var registration = '';
    if (rawRegistration.trim().isNotEmpty) {
      final result = normalizeRegistration(rawRegistration);
      switch (result) {
        case RegistrationValid(:final canonical):
          registration = canonical;
        case RegistrationInvalid(:final reasonKey):
          setState(() {
            _registrationError = switch (reasonKey) {
              'tooLong' => 'That is too long for a vehicle number.',
              _ => 'Check the vehicle number.',
            };
          });
          return null;
      }
    }

    final hasAnything = registration.isNotEmpty ||
        driverRaw.isNotEmpty ||
        bookingRaw.isNotEmpty ||
        _selectedType != VehicleType.other;
    if (!hasAnything) return null;

    return VehicleInfo(
      type: _selectedType,
      registrationNumber: registration.isEmpty ? null : registration,
      driverName: driverRaw.isEmpty ? null : driverRaw,
      bookingReference: bookingRaw.isEmpty ? null : bookingRaw,
    );
  }

  @override
  Widget build(BuildContext context) {
    final journey = ref.watch(journeyControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Safe journey')),
      body: switch (journey) {
        JourneyIdle() => _IdleForm(
            notice: journey.notice,
            registrationController: _registrationController,
            driverController: _driverController,
            bookingController: _bookingController,
            selectedType: _selectedType,
            onTypeChanged: (type) => setState(() => _selectedType = type),
            registrationError: _registrationError,
            driverError: _driverError,
            bookingError: _bookingError,
            onStart: () async {
              final vehicle = _vehicleFromForm();
              if (_hasErrors) return;
              await ref
                  .read(journeyControllerProvider.notifier)
                  .startJourney(vehicle: vehicle);
            },
          ),
        JourneyStarting() => const Center(child: CircularProgressIndicator()),
        JourneyActive() => _ActiveView(journey: journey),
        JourneyCompleted(
            :final reason,
            :final endedAt,
            :final startedAt,
            :final vehicle,
          ) =>
          _CompletedView(
            reason: reason,
            startedAt: startedAt,
            endedAt: endedAt,
            vehicle: vehicle,
            onDismiss: () => ref
                .read(journeyControllerProvider.notifier)
                .dismissCompletion(),
          ),
      },
    );
  }

  bool get _hasErrors =>
      _registrationError != null || _driverError != null || _bookingError != null;
}

class _IdleForm extends StatelessWidget {
  const _IdleForm({
    required this.notice,
    required this.registrationController,
    required this.driverController,
    required this.bookingController,
    required this.selectedType,
    required this.onTypeChanged,
    required this.registrationError,
    required this.driverError,
    required this.bookingError,
    required this.onStart,
  });

  final String? notice;
  final TextEditingController registrationController;
  final TextEditingController driverController;
  final TextEditingController bookingController;
  final VehicleType selectedType;
  final ValueChanged<VehicleType> onTypeChanged;
  final String? registrationError;
  final String? driverError;
  final String? bookingError;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Vehicle', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        DropdownButtonFormField<VehicleType>(
          key: const Key('journey-vehicle-type'),
          initialValue: selectedType,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final type in VehicleType.values)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (type) {
            if (type != null) onTypeChanged(type);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('journey-vehicle-registration'),
          controller: registrationController,
          textCapitalization: TextCapitalization.characters,
          autofillHints: const [],
          decoration: InputDecoration(
            labelText: 'Registration number',
            hintText: 'DL 01 AB 1234',
            errorText: registrationError,
          ),
        ),
        const SizedBox(height: 16),
        Text('Optional', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const Key('journey-driver-name'),
          controller: driverController,
          decoration: InputDecoration(
            labelText: 'Driver name',
            errorText: driverError,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('journey-booking-reference'),
          controller: bookingController,
          decoration: InputDecoration(
            labelText: 'Booking/reference',
            errorText: bookingError,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('journey-start'),
          onPressed: onStart,
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Start safe journey'),
        ),
        if (notice != null) ...[
          const SizedBox(height: 12),
          Text(
            notice!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// Vehicle card shown while travelling. Deliberately calm and secondary:
/// the emergency affordances live on their own screens and always dominate.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});

  final VehicleInfo vehicle;

  @override
  Widget build(BuildContext context) {
    final reg = vehicle.displayRegistrationNumber;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car_outlined, size: 18),
                const SizedBox(width: 6),
                Text(vehicle.type.label),
              ],
            ),
            if (reg != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  reg,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveView extends ConsumerStatefulWidget {
  const _ActiveView({required this.journey});

  final JourneyActive journey;

  @override
  ConsumerState<_ActiveView> createState() => _ActiveViewState();
}

class _ActiveViewState extends ConsumerState<_ActiveView> {
  @override
  void initState() {
    super.initState();
    // Elapsed-time ticker; cancelled on dispose so tests stay clean.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  late final Timer _ticker;

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final elapsed = DateTime.now().difference(journey.session.startedAt);
    final activeVehicle = journey.vehicle;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Journey running · ${_formatElapsed(elapsed)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text('Started at ${formatCapturedTime(journey.session.startedAt)}'),
        const SizedBox(height: 4),
        Text(
          'Location: connecting…',
          style: TextStyle(color: Colors.orange.shade800),
        ),
        if (activeVehicle != null && !activeVehicle.hasNoContent) ...[
          const SizedBox(height: 12),
          _VehicleCard(vehicle: activeVehicle),
        ],
        const SizedBox(height: 16),
        if (journey.shareExpired)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text(
                    'The journey link expired. Your location is no longer '
                    'being shared.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('journey-share-again'),
                    onPressed: () => ref
                        .read(journeyControllerProvider.notifier)
                        .shareAgain(widget.journey),
                    child: const Text('Share a new link'),
                  ),
                ],
              ),
            ),
          )
        else
          _ShareSection(journey: journey),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          key: const Key('journey-end'),
          onPressed: () =>
              ref.read(journeyControllerProvider.notifier).endJourney(),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Arrived — end journey'),
        ),
      ],
    );
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

extension on VehicleInfo {
  /// True when nothing meaningful was entered (Other type, no fields).
  bool get hasNoContent =>
      !hasRegistration &&
      driverName == null &&
      bookingReference == null &&
      type == VehicleType.other;
}

class _ShareSection extends ConsumerWidget {
  const _ShareSection({required this.journey});

  final JourneyActive journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = journey.shareUrl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sharing your journey'),
            const SizedBox(height: 4),
            Text(
              url.isEmpty
                  ? 'Waiting for a connection to create your link…'
                  : 'Expires at ${formatCapturedTime(journey.expiresAt)}',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('journey-share-button'),
                    onPressed: url.isEmpty
                        ? null
                        : () async {
                            await ref
                                .read(shareServiceProvider)
                                .shareText(buildJourneyShareMessage(
                                  startedAt: journey.session.startedAt,
                                  shareUrl: url,
                                  expiresAt: journey.expiresAt,
                                  vehicle: journey.vehicle,
                                ));
                          },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Send link'),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy link',
                  onPressed: url.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                        },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedView extends StatelessWidget {
  const _CompletedView({
    required this.reason,
    required this.startedAt,
    required this.endedAt,
    required this.vehicle,
    required this.onDismiss,
  });

  final JourneyEndReason reason;
  final DateTime startedAt;
  final DateTime endedAt;
  final VehicleInfo? vehicle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final escalated = reason == JourneyEndReason.escalatedToSos;
    final vehicleSummary = vehicle;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              escalated ? Icons.sos : Icons.check_circle_outline,
              size: 48,
              color: escalated
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              escalated
                  ? 'Emergency took over your journey'
                  : 'Journey ended',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (vehicleSummary != null && !vehicleSummary.hasNoContent) ...[
              _VehicleCard(vehicle: vehicleSummary),
              const SizedBox(height: 12),
            ],
            Text(
              'Start: ${formatCapturedTime(startedAt)}\n'
              'End: ${formatCapturedTime(endedAt)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              escalated
                  ? 'Your emergency alert is running. The journey link was '
                      'closed so your emergency can use the connection.'
                  : 'You arrived safely. Location sharing stopped.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('journey-dismiss'),
              onPressed: onDismiss,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
