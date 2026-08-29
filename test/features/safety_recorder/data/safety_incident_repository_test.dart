import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/features/safety_recorder/data/safety_incident_repository_impl.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_recorder_policy.dart';
import '../../../helpers/fakes.dart';

import '../safety_recorder_test_helpers.dart';

void main() {
  late FakePreferencesService prefs;
  late SafetyIncidentRepositoryImpl repo;

  setUp(() {
    prefs = FakePreferencesService();
    repo = SafetyIncidentRepositoryImpl(preferences: prefs);
  });

  group('SafetyIncidentRepositoryImpl', () {
    test('loadAll returns empty list when nothing stored', () async {
      final result = await repo.loadAll();
      expect(result.isOk, isTrue);
      expect(result.getOrNull(), isEmpty);
    });

    test('save and loadAll round-trips', () async {
      final incident = createTestIncident(id: 'inc_001');
      await repo.save(incident);

      final result = await repo.loadAll();
      expect(result.isOk, isTrue);
      final incidents = result.getOrNull()!;
      expect(incidents, hasLength(1));
      expect(incidents[0].id, equals('inc_001'));
    });

    test('save upserts by id', () async {
      final incident1 = createTestIncident(id: 'inc_001');
      await repo.save(incident1);

      final incident2 = createTestIncident(id: 'inc_001');
      await repo.save(incident2);

      final result = await repo.loadAll();
      expect(result.getOrNull(), hasLength(1));
    });

    test('save enforces max incident limit', () async {
      for (var i = 0; i < SafetyRecorderPolicy.maxIncidents + 5; i++) {
        await repo.save(createTestIncident(id: 'inc_${i.toString().padLeft(3, '0')}'));
      }

      final result = await repo.loadAll();
      expect(result.getOrNull(), hasLength(SafetyRecorderPolicy.maxIncidents));
    });

    test('delete removes an incident', () async {
      await repo.save(createTestIncident(id: 'inc_001'));
      await repo.save(createTestIncident(id: 'inc_002'));

      await repo.delete('inc_001');

      final result = await repo.loadAll();
      expect(result.getOrNull(), hasLength(1));
      expect(result.getOrNull()![0].id, equals('inc_002'));
    });

    test('clearAll removes all incidents', () async {
      await repo.save(createTestIncident(id: 'inc_001'));
      await repo.save(createTestIncident(id: 'inc_002'));

      await repo.clearAll();

      final result = await repo.loadAll();
      expect(result.getOrNull(), isEmpty);
    });

    test('sets storage version on first access', () async {
      await repo.loadAll();
      final version = await prefs.getInt(SafetyRecorderPolicy.storageVersionKey);
      expect(version, equals(SafetyRecorderPolicy.currentStorageVersion));
    });
  });
}
