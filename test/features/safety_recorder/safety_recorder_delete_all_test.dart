import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/safety_recorder/application/safety_recorder_controller.dart';
import 'package:guardianher/features/safety_recorder/data/safety_incident_repository.dart';
import 'package:guardianher/features/safety_recorder/data/safety_incident_repository_impl.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_incident.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/settings/application/privacy_providers.dart';

import '../../helpers/fakes.dart';
import 'safety_recorder_test_helpers.dart';

/// Repository that tracks clearAll calls.
class _TrackingRepository implements SafetyIncidentRepository {
  List<SafetyIncident> incidents = [];
  int clearAllCalls = 0;

  @override
  Future<Result<List<SafetyIncident>>> loadAll() async =>
      Ok(List.unmodifiable(incidents));

  @override
  Future<Result<void>> save(SafetyIncident incident) async {
    incidents.add(incident);
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    incidents.removeWhere((i) => i.id == id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> clearAll() async {
    clearAllCalls++;
    incidents.clear();
    return const Ok(null);
  }
}

void main() {
  group('Delete All Local Data: safety incidents', () {
    test('clearAllIncidents removes all incidents from recorder state',
        () async {
      final repo = _TrackingRepository();
      repo.incidents = [
        createTestIncident(id: 'd1'),
        createTestIncident(id: 'd2'),
      ];

      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(),
          safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ...safetyRecorderTestOverrides(),
        ],
      );
      container.read(sosControllerProvider.notifier);
      container.read(safetyRecorderProvider);
      addTearDown(container.dispose);

      // Wait for async _loadIncidents.
      await Future<void>.delayed(Duration.zero);
      final before = container.read(safetyRecorderProvider);
      expect(before.recentIncidents, hasLength(2));

      // Clear.
      await container
          .read(safetyRecorderProvider.notifier)
          .clearAllIncidents();

      final after = container.read(safetyRecorderProvider);
      expect(after.recentIncidents, isEmpty);
      expect(repo.clearAllCalls, equals(1));
    });

    test('PrivacyController.deleteAllLocalData clears safety incidents',
        () async {
      final repo = _TrackingRepository();
      repo.incidents = [
        createTestIncident(id: 'p1'),
        createTestIncident(id: 'p2'),
      ];

      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(),
          safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ...safetyRecorderTestOverrides(),
        ],
      );
      container.read(sosControllerProvider.notifier);
      container.read(safetyRecorderProvider);
      addTearDown(container.dispose);

      // Wait for async _loadIncidents.
      await Future<void>.delayed(Duration.zero);
      final before = container.read(safetyRecorderProvider);
      expect(before.recentIncidents, hasLength(2));

      // Trigger delete all data.
      final privacy = container.read(privacyControllerProvider.notifier);
      await privacy.deleteAllLocalData();

      final after = container.read(safetyRecorderProvider);
      expect(after.recentIncidents, isEmpty);
    });

    test('Safety Recorder shows empty state after delete-all', () async {
      final repo = _TrackingRepository();
      repo.incidents = [createTestIncident(id: 'empty_test')];

      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(),
          safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ...safetyRecorderTestOverrides(),
        ],
      );
      container.read(sosControllerProvider.notifier);
      container.read(safetyRecorderProvider);
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);

      final privacy = container.read(privacyControllerProvider.notifier);
      await privacy.deleteAllLocalData();

      final recorderState = container.read(safetyRecorderProvider);
      expect(recorderState.recentIncidents, isEmpty);
      expect(recorderState.currentIncident, isNull);
    });
  });

  group('Corrupted storage handling', () {
    test('corrupted JSON on load returns empty list without crashing', () async {
      final prefs = FakePreferencesService();
      // Store corrupted data directly.
      await prefs.setString(
        'safety_recorder_incidents_list',
        '{not valid json!!!',
      );

      final repo = SafetyIncidentRepositoryImpl(preferences: prefs);
      final result = await repo.loadAll();

      expect(result.isOk, isTrue);
      expect(result.getOrNull(), isEmpty);
    });

    test('future storage version returns empty list', () async {
      final prefs = FakePreferencesService();
      await prefs.setString(
        'safety_recorder_incidents_list',
        '{"version":99,"incidents":[]}',
      );

      final repo = SafetyIncidentRepositoryImpl(preferences: prefs);
      final result = await repo.loadAll();

      expect(result.isOk, isTrue);
      expect(result.getOrNull(), isEmpty);
    });

    test('missing incidents key returns empty list', () async {
      final prefs = FakePreferencesService();
      await prefs.setString(
        'safety_recorder_incidents_list',
        '{"version":1}',
      );

      final repo = SafetyIncidentRepositoryImpl(preferences: prefs);
      final result = await repo.loadAll();

      expect(result.isOk, isTrue);
      expect(result.getOrNull(), isEmpty);
    });
  });
}
