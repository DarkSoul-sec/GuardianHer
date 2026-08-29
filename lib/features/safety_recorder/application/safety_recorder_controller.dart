import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../features/check_in/application/check_in_providers.dart';
import '../../../features/check_in/application/check_in_state.dart';
import '../../../features/journey/application/journey_providers.dart';
import '../../../features/journey/domain/journey_state.dart';
import '../../../features/journey/domain/safety_recorder_events.dart';
import '../../../features/location/application/location_providers.dart';
import '../../../features/location/application/location_state.dart';
import '../../../features/safety_session/domain/safety_session_id.dart';
import '../../../features/sos/application/sos_actions_state.dart';
import '../../../features/sos/application/sos_providers.dart';
import '../../../features/sos/application/sos_state.dart';
import '../data/safety_incident_repository.dart';
import '../data/safety_incident_repository_impl.dart';
import '../domain/incident_integrity.dart';
import '../domain/safety_incident.dart';
import '../domain/safety_recorder_policy.dart';

/// The safety recorder provider.
final safetyRecorderProvider =
    NotifierProvider<SafetyRecorderController, SafetyRecorderState>(
  SafetyRecorderController.new,
);

/// Repository provider (wired to SharedPreferences impl).
final safetyIncidentRepositoryProvider = Provider<SafetyIncidentRepository>(
  (ref) => SafetyIncidentRepositoryImpl(
    preferences: ref.watch(preferencesServiceProvider),
  ),
);

/// State of the Safety Recorder.
class SafetyRecorderState {
  const SafetyRecorderState({
    this.currentIncident,
    this.recentIncidents = const [],
    this.isInitialized = false,
  });

  /// The incident currently being recorded (non-null during SOS/journey).
  final SafetyIncident? currentIncident;

  /// Completed incidents loaded from storage, newest first.
  final List<SafetyIncident> recentIncidents;

  /// Whether the controller has loaded persisted incidents.
  final bool isInitialized;

  SafetyRecorderState copyWith({
    SafetyIncident? Function()? currentIncident,
    List<SafetyIncident>? recentIncidents,
    bool? isInitialized,
  }) {
    return SafetyRecorderState(
      currentIncident:
          currentIncident != null ? currentIncident() : this.currentIncident,
      recentIncidents: recentIncidents ?? this.recentIncidents,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// App-rooted Safety Recorder controller.
///
/// Observes SOS, journey, location, communication, and check-in providers
/// to record privacy-safe events into an incident. On SOS activation, the
/// buffer is frozen and an incident is created. On SOS completion, the
/// incident is finalized and persisted.
///
/// The controller NEVER blocks, delays, or affects any safety feature.
/// All failures are swallowed internally.
class SafetyRecorderController extends Notifier<SafetyRecorderState> {
  /// Rolling buffer of recent events (pre-event window).
  final List<RecordedSafetyEvent> _buffer = [];

  /// The current incident being built.
  SafetyIncident? _activeIncident;

  /// Hash chain state for the active incident.
  String _lastHash = incidentGenesisHash;

  /// Previous location state for change detection.
  LocationStatus? _prevLocationStatus;

  /// Previous check-in status message for change detection.
  String? _prevCheckInStatus;

  /// Last known journey session id, carried from JourneyActive to JourneyCompleted.
  String _lastJourneySessionId = '';

  DateTime Function() get _clock => DateTime.now;

  SafetyIncidentRepository get _repo =>
      ref.read(safetyIncidentRepositoryProvider);

  @override
  SafetyRecorderState build() {
    // Load persisted incidents on build.
    _loadIncidents();

    // Observe SOS state changes.
    ref.listen(sosControllerProvider, (previous, next) {
      _onSosStateChanged(previous, next);
    });

    // Observe journey state changes.
    ref.listen(journeyControllerProvider, (previous, next) {
      _onJourneyStateChanged(previous, next);
    });

    // Observe location state changes (only records during active incident).
    ref.listen(locationControllerProvider, (previous, next) {
      _onLocationStateChanged(previous?.status, next.status);
    });

    // Observe communication actions via SOS actions state.
    ref.listen(sosActionsControllerProvider, (previous, next) {
      _onCommunicationStateChanged(previous, next);
    });

    // Observe check-in state changes.
    ref.listen(checkInControllerProvider, (previous, next) {
      _onCheckInStateChanged(previous, next);
    });

    return const SafetyRecorderState();
  }

  /// Loads persisted incidents from storage.
  Future<void> _loadIncidents() async {
    final result = await _repo.loadAll();
    result.fold(
      (incidents) {
        state = state.copyWith(
          recentIncidents: incidents,
          isInitialized: true,
        );
      },
      (_) {
        state = state.copyWith(isInitialized: true);
      },
    );
  }

  /// Records an event into the rolling buffer or active incident.
  ///
  /// This is fire-and-forget: failures are swallowed.
  void recordEvent({
    required SafetyEventType eventType,
    required String sessionId,
    Map<String, String> metadata = const {},
  }) {
    final event = RecordedSafetyEvent(
      eventId: generateRecorderEventId(),
      eventType: eventType,
      occurredAt: _clock(),
      sessionId: sessionId,
      metadata: metadata,
    );

    // Add to rolling buffer.
    _buffer.add(event);
    _trimBuffer();

    // If an incident is active, add to it.
    if (_activeIncident != null) {
      _addToIncident(event);
    }
  }

  /// Trims the rolling buffer to the policy window.
  void _trimBuffer() {
    final cutoff = _clock().subtract(
      Duration(minutes: SafetyRecorderPolicy.preEventWindowMinutes),
    );
    _buffer.removeWhere((e) => e.occurredAt.isBefore(cutoff));
    while (_buffer.length > SafetyRecorderPolicy.maxBufferSize) {
      _buffer.removeAt(0);
    }
  }

  /// Adds an event to the active incident and computes the hash chain link.
  void _addToIncident(RecordedSafetyEvent event) {
    final incident = _activeIncident;
    if (incident == null) return;

    final hash = computeIncidentHash(
      previousHash: _lastHash,
      event: event,
    );
    _lastHash = hash;

    _activeIncident = SafetyIncident(
      id: incident.id,
      status: incident.status,
      createdAt: incident.createdAt,
      endedAt: incident.endedAt,
      events: [...incident.events, event],
      hashes: [...incident.hashes, hash],
      genesisHash: incident.genesisHash,
      vehicleType: incident.vehicleType ?? _vehicleTypeFromMetadata(event.metadata),
      hasVehicleRegistration:
          incident.hasVehicleRegistration || _hasRegistration(event.metadata),
    );

    state = state.copyWith(currentIncident: () => _activeIncident);
  }

  VehicleType? _vehicleTypeFromMetadata(Map<String, String> metadata) {
    final typeName = metadata[SafetyEventMetadataKey.vehicleType];
    if (typeName == null) return null;
    return VehicleType.values.firstWhere(
      (v) => v.name == typeName,
      orElse: () => VehicleType.other,
    );
  }

  bool _hasRegistration(Map<String, String> metadata) {
    return metadata[SafetyEventMetadataKey.hasRegistration] == 'true';
  }

  String _sosSessionId() {
    final incident = _activeIncident;
    if (incident == null) return '';
    // Use the incident's own id as session reference when no SOS event id is
    // available (e.g. journey or location events outside SOS).
    return incident.id;
  }

  // ── SOS state transitions ──────────────────────────────────────────────────

  void _onSosStateChanged(SosState? previous, SosState next) {
    switch (next) {
      case SosActive():
        _onSosActivated(next);
      case SosCancelling():
        _onSosCancelling(next);
      case SosCompleted():
        _onSosCompleted(next);
      case SosIdle():
        _onSosIdle();
      default:
        break;
    }
  }

  void _onSosActivated(SosActive active) {
    if (_activeIncident != null) return; // Already recording.

    final incidentId = SafetySessionId.generate().value;
    final now = _clock();

    // Capture buffered events.
    final bufferedEvents = List<RecordedSafetyEvent>.from(_buffer);
    _buffer.clear();

    // Build incident with buffered events.
    var hash = incidentGenesisHash;
    final hashes = <String>[];
    for (final event in bufferedEvents) {
      hash = computeIncidentHash(previousHash: hash, event: event);
      hashes.add(hash);
    }
    _lastHash = hash;

    _activeIncident = SafetyIncident(
      id: incidentId,
      status: SafetyIncidentStatus.recording,
      createdAt: now,
      events: bufferedEvents,
      hashes: hashes,
      genesisHash: incidentGenesisHash,
    );

    // Record the SOS activation event.
    recordEvent(
      eventType: SafetyEventType.sosActivated,
      sessionId: active.event.id.value,
    );

    state = state.copyWith(currentIncident: () => _activeIncident);
  }

  void _onSosCancelling(SosCancelling cancelling) {
    if (_activeIncident == null) return;

    // Record the SOS cancellation event before freezing.
    recordEvent(
      eventType: SafetyEventType.sosCancellationStarted,
      sessionId: cancelling.event.id.value,
    );

    _activeIncident = _activeIncident!.copyWith(
      status: SafetyIncidentStatus.frozen,
    );
    state = state.copyWith(currentIncident: () => _activeIncident);
  }

  void _onSosCompleted(SosCompleted completed) {
    if (_activeIncident == null) return;

    // Record the SOS completion event.
    recordEvent(
      eventType: SafetyEventType.sosCompleted,
      sessionId: completed.event.id.value,
    );

    // Finalize and persist.
    _finalizeIncident();
  }

  void _onSosIdle() {
    if (_activeIncident == null) return;
    // If we reach idle without going through completed, finalize anyway.
    _finalizeIncident();
  }

  /// Finalizes the active incident: sets status, persists, and clears.
  void _finalizeIncident() {
    final incident = _activeIncident;
    if (incident == null) return;

    final finalized = SafetyIncident(
      id: incident.id,
      status: SafetyIncidentStatus.completed,
      createdAt: incident.createdAt,
      endedAt: _clock(),
      events: incident.events,
      hashes: incident.hashes,
      genesisHash: incident.genesisHash,
      vehicleType: incident.vehicleType,
      hasVehicleRegistration: incident.hasVehicleRegistration,
    );

    _activeIncident = null;
    _lastHash = incidentGenesisHash;
    _prevLocationStatus = null;
    _prevCheckInStatus = null;
    _lastJourneySessionId = '';

    // Persist (fire-and-forget). Retention is enforced by the repository.
    _persistIncident(finalized);

    state = state.copyWith(
      currentIncident: () => null,
      recentIncidents: [finalized, ...state.recentIncidents],
    );
  }

  /// Persists an incident to storage. Retention is enforced by the
  /// repository's max-incident cap — no second eviction pass needed.
  Future<void> _persistIncident(SafetyIncident incident) async {
    await _repo.save(incident);
  }

  // ── Journey state transitions ──────────────────────────────────────────────

  void _onJourneyStateChanged(JourneyState? previous, JourneyState next) {
    switch (next) {
      case JourneyActive():
        _onJourneyStarted(next);
      case JourneyCompleted():
        _onJourneyCompleted(next);
      default:
        break;
    }
  }

  void _onJourneyStarted(JourneyActive active) {
    final sessionId = active.session.id.value;
    _lastJourneySessionId = sessionId;

    recordEvent(
      eventType: SafetyEventType.journeyStarted,
      sessionId: sessionId,
    );

    // Record vehicle attachment if present.
    final vehicle = active.vehicle;
    if (vehicle != null) {
      recordEvent(
        eventType: SafetyEventType.vehicleAttached,
        sessionId: sessionId,
        metadata: {
          SafetyEventMetadataKey.vehicleType: vehicle.type.name,
          SafetyEventMetadataKey.hasRegistration:
              vehicle.hasRegistration.toString(),
        },
      );
    }
  }

  void _onJourneyCompleted(JourneyCompleted completed) {
    recordEvent(
      eventType: SafetyEventType.journeyEnded,
      sessionId: _lastJourneySessionId,
      metadata: {
        SafetyEventMetadataKey.endReason: completed.reason.name,
      },
    );
  }

  // ── Location state transitions ─────────────────────────────────────────────

  void _onLocationStateChanged(
    LocationStatus? previous,
    LocationStatus next,
  ) {
    if (previous == next) return;
    if (_activeIncident == null) return;

    final sessionId = _sosSessionId();
    if (sessionId.isEmpty) return;

    switch (next) {
      case LocationStatus.loading:
        recordEvent(
          eventType: SafetyEventType.locationCaptureStarted,
          sessionId: sessionId,
        );
      case LocationStatus.captured:
        recordEvent(
          eventType: SafetyEventType.locationCaptured,
          sessionId: sessionId,
        );
      case LocationStatus.timeout:
        recordEvent(
          eventType: SafetyEventType.locationTimeout,
          sessionId: sessionId,
        );
      case LocationStatus.unavailable:
        recordEvent(
          eventType: SafetyEventType.locationUnavailable,
          sessionId: sessionId,
        );
      case LocationStatus.denied:
        recordEvent(
          eventType: SafetyEventType.locationPermissionDenied,
          sessionId: sessionId,
        );
      case LocationStatus.servicesDisabled:
        recordEvent(
          eventType: SafetyEventType.locationServicesDisabled,
          sessionId: sessionId,
        );
      case LocationStatus.idle:
        break;
    }
  }

  // ── Communication state transitions ────────────────────────────────────────

  void _onCommunicationStateChanged(
    SosActionsState? previous,
    SosActionsState next,
  ) {
    if (_activeIncident == null) return;

    final sessionId = _sosSessionId();
    if (sessionId.isEmpty) return;

    final prevOutcome = previous?.lastOutcome;
    final nextOutcome = next.lastOutcome;

    // Only record when a NEW outcome appears (not a repeat of the same one).
    if (nextOutcome == null || nextOutcome == prevOutcome) return;

    recordEvent(
      eventType: nextOutcome.isSuccess
          ? SafetyEventType.communicationHandedOff
          : SafetyEventType.communicationFailed,
      sessionId: sessionId,
      metadata: {
        SafetyEventMetadataKey.channelType: nextOutcome.kind.name,
      },
    );
  }

  // ── Check-in state transitions ─────────────────────────────────────────────

  void _onCheckInStateChanged(
    CheckInState? previous,
    CheckInState next,
  ) {
    if (_activeIncident == null) return;

    final sessionId = _sosSessionId();
    if (sessionId.isEmpty) return;

    final prevStatus = _prevCheckInStatus;
    final nextStatus = next.statusMessage;
    _prevCheckInStatus = nextStatus;

    // Only record when statusMessage changes to a new value.
    if (nextStatus == null || nextStatus == prevStatus) return;

    // Map check-in status messages to event types.
    if (nextStatus.toLowerCase().contains('opened') ||
        nextStatus.toLowerCase().contains('sent')) {
      recordEvent(
        eventType: SafetyEventType.checkInCompleted,
        sessionId: sessionId,
      );
    }
  }

  // ── User actions ──────────────────────────────────────────────────────────

  /// Deletes an incident (user action from the UI).
  Future<void> deleteIncident(String id) async {
    await _repo.delete(id);
    state = state.copyWith(
      recentIncidents: state.recentIncidents.where((i) => i.id != id).toList(),
    );
  }

  /// Clears all incidents (privacy action).
  Future<void> clearAllIncidents() async {
    await _repo.clearAll();
    state = state.copyWith(recentIncidents: const []);
  }
}
