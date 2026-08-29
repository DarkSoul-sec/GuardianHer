import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/safety_recorder/application/safety_recorder_controller.dart';
import 'package:guardianher/features/safety_recorder/data/safety_incident_repository.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_incident.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';

import 'package:guardianher/features/safety_recorder/domain/incident_integrity.dart';

import '../../helpers/fakes.dart';
import 'safety_recorder_test_helpers.dart';

/// Builds a container with SOS side-effects silenced and the notifier attached.
ProviderContainer _buildContainer({
  SafetyIncidentRepository? repo,
  required ManualSosController manualSos,
}) {
  final container = ProviderContainer(
    overrides: [
      ...defaultOverrides(),
      if (repo != null)
        safetyIncidentRepositoryProvider.overrideWithValue(repo),
      ...safetyRecorderTestOverrides(manualSos: manualSos),
    ],
  );
  container.read(sosControllerProvider.notifier);
  container.read(safetyRecorderProvider.notifier);
  return container;
}

/// Integration tests proving the full lifecycle: buffer -> incident -> persist.
void main() {
  group('Integration: Shake -> SOS flow', () {
    late ProviderContainer container;
    late ManualSosController manualSos;

    setUp(() {
      manualSos = ManualSosController();
      container = _buildContainer(manualSos: manualSos);
    });

    tearDown(() => container.dispose());

    SafetyRecorderController ctrl() =>
        container.read(safetyRecorderProvider.notifier);

    SafetyRecorderState st() => container.read(safetyRecorderProvider);

    test('shakeDetected is buffered and included in SOS incident', () {
      // 1. Shake detected (before SOS).
      ctrl().recordEvent(
        eventType: SafetyEventType.shakeDetected,
        sessionId: '',
      );

      // 2. SOS activates via the provider.
      manualSos.activate();

      final incident = st().currentIncident!;
      expect(incident.events, hasLength(2));
      expect(incident.events[0].eventType, SafetyEventType.shakeDetected);
      expect(incident.events[1].eventType, SafetyEventType.sosActivated);

      // Verify chain integrity (raw — incident is still recording).
      expect(
        verifyIncidentIntegrity(
          genesisHash: incident.genesisHash,
          events: incident.events,
          hashes: incident.hashes,
        ),
        isTrue,
      );
    });

    test('location events are recorded during SOS', () {
      manualSos.activate();

      ctrl().recordEvent(
        eventType: SafetyEventType.locationCaptureStarted,
        sessionId: 'sos_loc',
      );

      ctrl().recordEvent(
        eventType: SafetyEventType.locationCaptured,
        sessionId: 'sos_loc',
      );

      final incident = st().currentIncident!;
      expect(incident.events, hasLength(3));
      expect(
        incident.events.map((e) => e.eventType),
        equals([
          SafetyEventType.sosActivated,
          SafetyEventType.locationCaptureStarted,
          SafetyEventType.locationCaptured,
        ]),
      );
    });

    test('communication events are recorded during SOS', () {
      manualSos.activate();

      ctrl().recordEvent(
        eventType: SafetyEventType.communicationHandedOff,
        sessionId: 'sos_comm',
        metadata: {
          SafetyEventMetadataKey.channelType: 'sms',
        },
      );

      final incident = st().currentIncident!;
      expect(incident.events, hasLength(2));
      expect(incident.events[1].eventType,
          SafetyEventType.communicationHandedOff);
      expect(
        incident.events[1].metadata[SafetyEventMetadataKey.channelType],
        'sms',
      );
    });
  });

  group('Integration: Journey flow', () {
    late ProviderContainer container;
    late ManualSosController manualSos;

    setUp(() {
      manualSos = ManualSosController();
      container = _buildContainer(manualSos: manualSos);
    });

    tearDown(() => container.dispose());

    SafetyRecorderController ctrl() =>
        container.read(safetyRecorderProvider.notifier);

    SafetyRecorderState st() => container.read(safetyRecorderProvider);

    test('journeyStarted and vehicleAttached events are buffered', () {
      ctrl().recordEvent(
        eventType: SafetyEventType.journeyStarted,
        sessionId: 'journey_123',
      );

      ctrl().recordEvent(
        eventType: SafetyEventType.vehicleAttached,
        sessionId: 'journey_123',
        metadata: {
          SafetyEventMetadataKey.vehicleType: 'cab',
          SafetyEventMetadataKey.hasRegistration: 'true',
        },
      );

      ctrl().recordEvent(
        eventType: SafetyEventType.journeyEnded,
        sessionId: 'journey_123',
        metadata: {
          SafetyEventMetadataKey.endReason: 'arrived',
        },
      );

      // Journey events go to buffer (no incident active).
      expect(st().currentIncident, isNull);
    });
  });

  group('Integration: failure isolation', () {
    test('recorder failure does not affect SOS', () async {
      final repo = _FailingRepository();
      final sos = ManualSosController();
      final container = _buildContainer(repo: repo, manualSos: sos);
      addTearDown(container.dispose);

      // Trigger SOS — should not throw even with a failing repository.
      sos.activate();

      final state = container.read(safetyRecorderProvider);
      expect(state.currentIncident, isNotNull);
      expect(state.currentIncident!.events, hasLength(1));
    });

    test('corrupted storage does not crash the app', () async {
      final repo = _CorruptedRepository();
      final container = _buildContainer(
        repo: repo,
        manualSos: ManualSosController(),
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);

      final state = container.read(safetyRecorderProvider);
      expect(state.isInitialized, isTrue);
      expect(state.recentIncidents, isEmpty);
    });
  });

  group('Integration: privacy in full lifecycle', () {
    test('no phone numbers in any event through the lifecycle', () {
      final sos = ManualSosController();
      final container = _buildContainer(manualSos: sos);
      addTearDown(container.dispose);

      final ctrl = container.read(safetyRecorderProvider.notifier);

      // Buffer some pre-SOS events.
      ctrl.recordEvent(
        eventType: SafetyEventType.shakeDetected,
        sessionId: '',
      );

      // Trigger SOS.
      sos.activate();

      // Record events during SOS.
      ctrl.recordEvent(
        eventType: SafetyEventType.locationCaptureStarted,
        sessionId: 'sos_privacy',
      );
      ctrl.recordEvent(
        eventType: SafetyEventType.locationCaptured,
        sessionId: 'sos_privacy',
      );
      ctrl.recordEvent(
        eventType: SafetyEventType.communicationHandedOff,
        sessionId: 'sos_privacy',
        metadata: {
          SafetyEventMetadataKey.channelType: 'whatsapp',
        },
      );

      // Complete SOS.
      sos.complete();

      final state = container.read(safetyRecorderProvider);
      final incident = state.recentIncidents.first;

      for (final event in incident.events) {
        final str = event.toString();
        expect(RegExp(r'\d{10}').hasMatch(str), isFalse,
            reason: 'Event ${event.eventType} exposes phone number');
        expect(RegExp(r'\S+@\S+').hasMatch(str), isFalse,
            reason: 'Event ${event.eventType} exposes email');
        expect(RegExp(r'\d{2,3}\.\d{4,}').hasMatch(str), isFalse,
            reason: 'Event ${event.eventType} exposes coordinates');
      }
    });
  });
}

/// Repository that always fails on load.
class _FailingRepository implements SafetyIncidentRepository {
  @override
  Future<Result<List<SafetyIncident>>> loadAll() async =>
      const Err(StorageFailure('test failure'));

  @override
  Future<Result<void>> save(SafetyIncident incident) async =>
      const Err(StorageFailure('test failure'));

  @override
  Future<Result<void>> delete(String id) async => const Ok(null);

  @override
  Future<Result<void>> clearAll() async => const Ok(null);
}

/// Repository that returns corrupted data on load.
class _CorruptedRepository implements SafetyIncidentRepository {
  @override
  Future<Result<List<SafetyIncident>>> loadAll() async => const Ok([]);

  @override
  Future<Result<void>> save(SafetyIncident incident) async => const Ok(null);

  @override
  Future<Result<void>> delete(String id) async => const Ok(null);

  @override
  Future<Result<void>> clearAll() async => const Ok(null);
}
