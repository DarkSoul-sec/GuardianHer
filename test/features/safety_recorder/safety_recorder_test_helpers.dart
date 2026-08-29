import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/features/check_in/application/check_in_controller.dart';
import 'package:guardianher/features/check_in/application/check_in_providers.dart';
import 'package:guardianher/features/check_in/application/check_in_state.dart';
import 'package:guardianher/features/check_in/domain/check_in_settings.dart';
import 'package:guardianher/features/journey/application/journey_controller.dart';
import 'package:guardianher/features/journey/application/journey_providers.dart';
import 'package:guardianher/features/journey/domain/journey_state.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/location/application/location_controller.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/safety_recorder/domain/incident_integrity.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_incident.dart';
import 'package:guardianher/features/sos/application/sos_action_controller.dart';
import 'package:guardianher/features/sos/application/sos_actions_state.dart';
import 'package:guardianher/features/sos/application/sos_controller.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/domain/sos_status.dart';

/// Creates a test incident with a valid hash chain.
SafetyIncident createTestIncident({
  String? id,
  SafetyIncidentStatus status = SafetyIncidentStatus.completed,
  List<SafetyEventType>? eventTypes,
  DateTime? createdAt,
}) {
  final types = eventTypes ?? [SafetyEventType.sosActivated];
  final events = <RecordedSafetyEvent>[];
  final hashes = <String>[];
  var prev = incidentGenesisHash;

  for (var i = 0; i < types.length; i++) {
    final event = RecordedSafetyEvent(
      eventId: 'evt_${id ?? 'test'}_$i',
      eventType: types[i],
      occurredAt:
          (createdAt ?? DateTime.utc(2026, 1, 1)).add(Duration(minutes: i)),
      sessionId: 'session_${id ?? 'test'}',
    );
    events.add(event);
    final hash = computeIncidentHash(previousHash: prev, event: event);
    hashes.add(hash);
    prev = hash;
  }

  return SafetyIncident(
    id: id ?? 'test_incident',
    status: status,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    endedAt: status == SafetyIncidentStatus.completed
        ? (createdAt ?? DateTime.utc(2026, 1, 1))
            .add(const Duration(hours: 1))
        : null,
    events: events,
    hashes: hashes,
    genesisHash: incidentGenesisHash,
  );
}

/// Creates a test [SosEvent] with sensible defaults.
SosEvent createTestSosEvent({
  SosStatus status = SosStatus.active,
  DateTime? now,
}) {
  final time = now ?? DateTime.utc(2026, 1, 1, 12);
  return SosEvent(
    id: SosEventId.generate(),
    startedAt: time,
    status: status,
    countdownDuration: Duration.zero,
    activatedAt: status == SosStatus.active ? time : null,
    completedAt: status == SosStatus.completed ? time : null,
    reason: status == SosStatus.completed
        ? SosTerminationReason.completed
        : null,
  );
}

/// A manual SOS controller that allows tests to emit states directly.
///
/// Extends [SosController] so it can be used as an override for
/// [sosControllerProvider]. Overrides [build] to avoid reading the real
/// timer/clock providers which are not available in unit tests.
class ManualSosController extends SosController {
  @override
  SosState build() => const SosIdle();

  void emit(SosState newState) => state = newState;

  void activate() => state = SosActive(event: createTestSosEvent());

  void complete() => state =
      SosCompleted(event: createTestSosEvent(status: SosStatus.completed));

  void idle() => state = const SosIdle();
}

// ---------------------------------------------------------------------------
// Minimal fakes for providers that SafetyRecorderController.build() listens to.
// ---------------------------------------------------------------------------

/// No-op SOS action controller (prevents vibration/notification side-effects).
class FakeSosActionController extends SosActionController {
  @override
  SosActionsState build() => const SosActionsState();
}

/// No-op journey controller (returns idle, no platform reads in build).
class FakeJourneyController extends JourneyController {
  @override
  JourneyState build() => const JourneyIdle();
}

/// No-op location controller (returns idle, no platform reads in build).
class FakeLocationController extends LocationController {
  @override
  LocationState build() => const LocationState();
}

/// No-op check-in controller (returns initial settings, no platform reads).
class FakeCheckInController extends CheckInController {
  @override
  CheckInState build() => const CheckInState(
        settings: CheckInSettings.initial,
      );
}

/// Provides the complete set of overrides needed to run safety recorder tests
/// without any platform channel calls or cascading provider initializations.
List<Override> safetyRecorderTestOverrides({
  ManualSosController? manualSos,
}) {
  return [
    sosControllerProvider.overrideWith(() => manualSos ?? ManualSosController()),
    sosActionsControllerProvider
        .overrideWith(() => FakeSosActionController()),
    journeyControllerProvider
        .overrideWith(() => FakeJourneyController()),
    locationControllerProvider
        .overrideWith(() => FakeLocationController()),
    checkInControllerProvider
        .overrideWith(() => FakeCheckInController()),
  ];
}
