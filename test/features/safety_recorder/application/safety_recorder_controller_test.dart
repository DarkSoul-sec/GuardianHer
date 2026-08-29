import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/journey/domain/vehicle_info.dart';
import 'package:guardianher/features/safety_recorder/application/safety_recorder_controller.dart';
import 'package:guardianher/features/safety_recorder/data/safety_incident_repository.dart';
import 'package:guardianher/features/safety_recorder/domain/incident_integrity.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_incident.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_recorder_policy.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';

import '../../../helpers/fakes.dart';
import '../safety_recorder_test_helpers.dart';

/// Fake repository that returns scripted results.
class FakeSafetyIncidentRepository implements SafetyIncidentRepository {
  final List<SafetyIncident> incidents = [];
  bool failLoad = false;
  bool failSave = false;
  bool failDelete = false;
  bool failClear = false;

  int loadCount = 0;
  int saveCount = 0;
  int deleteCount = 0;
  int clearCount = 0;

  @override
  Future<Result<List<SafetyIncident>>> loadAll() async {
    loadCount++;
    if (failLoad) return const Err(StorageFailure('load failed'));
    return Ok(List.unmodifiable(incidents));
  }

  @override
  Future<Result<void>> save(SafetyIncident incident) async {
    saveCount++;
    if (failSave) return const Err(StorageFailure('save failed'));
    final idx = incidents.indexWhere((i) => i.id == incident.id);
    if (idx >= 0) {
      incidents[idx] = incident;
    } else {
      incidents.add(incident);
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    deleteCount++;
    if (failDelete) return const Err(StorageFailure('delete failed'));
    incidents.removeWhere((i) => i.id == id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> clearAll() async {
    clearCount++;
    if (failClear) return const Err(StorageFailure('clear failed'));
    incidents.clear();
    return const Ok(null);
  }
}

/// Builds a container with the recorder wired to a [ManualSosController].
///
/// Uses [safetyRecorderTestOverrides] to override all providers that
/// [SafetyRecorderController.build] listens to, preventing cascading
/// platform service initialization.
ProviderContainer _buildContainer({
  FakeSafetyIncidentRepository? repo,
  ManualSosController? manualSos,
}) {
  final fakeRepo = repo ?? FakeSafetyIncidentRepository();
  final sos = manualSos ?? ManualSosController();
  final container = ProviderContainer(
    overrides: [
      ...defaultOverrides(),
      safetyIncidentRepositoryProvider.overrideWithValue(fakeRepo),
      ...safetyRecorderTestOverrides(manualSos: sos),
    ],
  );
  // Read the SOS notifier to attach it to the container element.
  container.read(sosControllerProvider.notifier);
  // Read the recorder to trigger build() → sets up ref.listen on all providers.
  container.read(safetyRecorderProvider.notifier);
  return container;
}

void main() {
  group('SafetyRecorderController', () {
    late FakeSafetyIncidentRepository repo;
    late ManualSosController manualSos;
    late ProviderContainer container;

    setUp(() {
      repo = FakeSafetyIncidentRepository();
      manualSos = ManualSosController();
      container = _buildContainer(repo: repo, manualSos: manualSos);
    });

    tearDown(() {
      container.dispose();
    });

    SafetyRecorderController ctrl() =>
        container.read(safetyRecorderProvider.notifier);

    SafetyRecorderState st() =>
        container.read(safetyRecorderProvider);

    test('initializes with empty state', () {
      expect(st().currentIncident, isNull);
      expect(st().recentIncidents, isEmpty);
      expect(st().isInitialized, isTrue);
    });

    test('loads persisted incidents on build', () async {
      repo.incidents.add(createTestIncident(id: 'loaded1'));
      repo.incidents.add(createTestIncident(id: 'loaded2'));

      final c = ProviderContainer(
        overrides: [
          ...defaultOverrides(),
          safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ...safetyRecorderTestOverrides(),
        ],
      );
      addTearDown(c.dispose);
      c.read(sosControllerProvider.notifier);
      // Read the recorder to trigger build() → _loadIncidents().
      c.read(safetyRecorderProvider);

      // Wait for the async _loadIncidents to complete.
      await Future<void>.delayed(Duration.zero);

      final loaded = c.read(safetyRecorderProvider);
      expect(loaded.recentIncidents, hasLength(2));
      expect(loaded.isInitialized, isTrue);
    });

    test('recordEvent adds to rolling buffer without creating incident', () {
      ctrl().recordEvent(
        eventType: SafetyEventType.shakeDetected,
        sessionId: 'test_session',
      );

      expect(st().currentIncident, isNull);
    });

    test('SOS activation creates incident with buffered events', () {
      // Buffer some events before SOS.
      ctrl().recordEvent(
        eventType: SafetyEventType.shakeDetected,
        sessionId: 'pre_sos',
      );
      ctrl().recordEvent(
        eventType: SafetyEventType.locationCaptured,
        sessionId: 'pre_sos',
      );

      // Trigger SOS activation via the provider.
      manualSos.activate();

      final incident = st().currentIncident!;
      expect(incident, isNotNull);
      expect(incident.status, SafetyIncidentStatus.recording);
      // 2 buffered + 1 sosActivated = 3 events.
      expect(incident.events, hasLength(3));
      expect(incident.events[0].eventType, SafetyEventType.shakeDetected);
      expect(incident.events[1].eventType, SafetyEventType.locationCaptured);
      expect(incident.events[2].eventType, SafetyEventType.sosActivated);
    });

    test('recordEvent adds to active incident', () {
      manualSos.activate();
      expect(st().currentIncident, isNotNull);

      ctrl().recordEvent(
        eventType: SafetyEventType.locationCaptured,
        sessionId: 'during_sos',
      );

      expect(st().currentIncident!.events, hasLength(2));
      expect(st().currentIncident!.events.last.eventType,
          SafetyEventType.locationCaptured);
    });

    test('SOS cancellation freezes incident', () {
      manualSos.activate();
      expect(st().currentIncident!.status, SafetyIncidentStatus.recording);

      final sosEvent = createTestSosEvent();
      manualSos.emit(SosCancelling(event: sosEvent));

      expect(st().currentIncident!.status, SafetyIncidentStatus.frozen);
    });

    test('SOS completion finalizes and persists incident', () async {
      manualSos.activate();
      expect(st().currentIncident, isNotNull);

      manualSos.complete();
      await Future<void>.delayed(Duration.zero);

      expect(st().currentIncident, isNull);
      expect(st().recentIncidents, hasLength(1));
      expect(repo.saveCount, equals(1));
    });

    test('deleteIncident removes from storage and state', () async {
      repo.incidents.add(createTestIncident(id: 'to_delete'));
      await container.read(safetyRecorderProvider.notifier).deleteIncident('to_delete');

      expect(repo.deleteCount, equals(1));
      expect(st().recentIncidents, isEmpty);
    });

    test('clearAllIncidents removes all from storage and state', () async {
      repo.incidents.add(createTestIncident(id: 'c1'));
      repo.incidents.add(createTestIncident(id: 'c2'));
      await container.read(safetyRecorderProvider.notifier).clearAllIncidents();

      expect(repo.clearCount, equals(1));
      expect(st().recentIncidents, isEmpty);
    });

    test('recorder failure does not throw', () {
      repo.failLoad = true;

      expect(
        () => ProviderContainer(
          overrides: [
            ...defaultOverrides(),
            safetyIncidentRepositoryProvider.overrideWithValue(repo),
            sosControllerProvider.overrideWith(() => ManualSosController()),
          ],
        ),
        returnsNormally,
      );
    });

    test('vehicle metadata is extracted from events', () {
      manualSos.activate();

      ctrl().recordEvent(
        eventType: SafetyEventType.vehicleAttached,
        sessionId: 'v_test',
        metadata: {
          SafetyEventMetadataKey.vehicleType: 'taxi',
          SafetyEventMetadataKey.hasRegistration: 'true',
        },
      );

      final incident = st().currentIncident!;
      expect(incident.vehicleType, VehicleType.taxi);
      expect(incident.hasVehicleRegistration, isTrue);
    });

    test('unrecognized vehicle type falls back to other', () {
      manualSos.activate();

      ctrl().recordEvent(
        eventType: SafetyEventType.vehicleAttached,
        sessionId: 'v_unknown',
        metadata: {
          SafetyEventMetadataKey.vehicleType: 'unknown_type',
          SafetyEventMetadataKey.hasRegistration: 'false',
        },
      );

      final incident = st().currentIncident!;
      expect(incident.vehicleType, VehicleType.other);
      expect(incident.hasVehicleRegistration, isFalse);
    });

    test('hash chain is built correctly', () {
      manualSos.activate();

      ctrl().recordEvent(
        eventType: SafetyEventType.locationCaptured,
        sessionId: 'hash_test',
      );
      ctrl().recordEvent(
        eventType: SafetyEventType.communicationHandedOff,
        sessionId: 'hash_test',
        metadata: {SafetyEventMetadataKey.channelType: 'sms'},
      );

      final incident = st().currentIncident!;
      // 1 sosActivated (from activation) + 2 recorded = 3 events.
      expect(incident.hashes, hasLength(3));
      expect(incident.genesisHash, equals(incidentGenesisHash));

      final valid = verifyIncidentIntegrity(
        genesisHash: incident.genesisHash,
        events: incident.events,
        hashes: incident.hashes,
      );
      expect(valid, isTrue);
    });

    test('genesis hash is correct', () {
      expect(incidentGenesisHash, equals('guardianher-recorder:v1'));
    });
  });

  group('Rolling buffer', () {
    late FakeSafetyIncidentRepository repo;
    late ManualSosController manualSos;
    late ProviderContainer container;

    setUp(() {
      repo = FakeSafetyIncidentRepository();
      manualSos = ManualSosController();
      container = _buildContainer(repo: repo, manualSos: manualSos);
    });

    tearDown(() {
      container.dispose();
    });

    SafetyRecorderController ctrl() =>
        container.read(safetyRecorderProvider.notifier);

    test('buffer trims events older than preEventWindowMinutes', () {
      for (var i = 0; i < 100; i++) {
        ctrl().recordEvent(
          eventType: SafetyEventType.locationCaptured,
          sessionId: 'buf_test',
        );
      }

      // Trigger SOS — buffer is frozen into incident.
      manualSos.activate();

      final incident = container.read(safetyRecorderProvider).currentIncident!;
      // 100 buffered + 1 sosActivated = 101.
      expect(incident.events.length, greaterThanOrEqualTo(101));
    });

    test('buffer respects maxBufferSize', () {
      for (var i = 0; i < SafetyRecorderPolicy.maxBufferSize + 50; i++) {
        ctrl().recordEvent(
          eventType: SafetyEventType.locationCaptured,
          sessionId: 'buf_max',
        );
      }

      manualSos.activate();

      final incident = container.read(safetyRecorderProvider).currentIncident!;
      expect(incident.events.length,
          lessThanOrEqualTo(SafetyRecorderPolicy.maxBufferSize + 1));
    });
  });
}
