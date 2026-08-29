import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/journey/domain/vehicle_info.dart';
import 'package:guardianher/features/safety_recorder/data/safety_event_serializer.dart';
import 'package:guardianher/features/safety_recorder/domain/incident_integrity.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_incident.dart';

void main() {
  group('SafetyEventSerializer', () {
    SafetyIncident _createTestIncident({
      String? id,
      List<SafetyEventType>? eventTypes,
    }) {
      final types = eventTypes ?? [SafetyEventType.sosActivated, SafetyEventType.sosCompleted];
      final events = <RecordedSafetyEvent>[];
      final hashes = <String>[];
      var prev = incidentGenesisHash;

      for (var i = 0; i < types.length; i++) {
        final event = RecordedSafetyEvent(
          eventId: 'event_$i',
          eventType: types[i],
          occurredAt: DateTime.utc(2026, 1, 1, 12, i),
          sessionId: 'session_001',
        );
        events.add(event);
        final hash = computeIncidentHash(previousHash: prev, event: event);
        hashes.add(hash);
        prev = hash;
      }

      return SafetyIncident(
        id: id ?? 'incident_001',
        status: SafetyIncidentStatus.completed,
        createdAt: DateTime.utc(2026, 1, 1, 12),
        endedAt: DateTime.utc(2026, 1, 1, 13),
        events: events,
        hashes: hashes,
        genesisHash: incidentGenesisHash,
        vehicleType: VehicleType.taxi,
        hasVehicleRegistration: true,
      );
    }

    test('round-trips a single incident', () {
      final incident = _createTestIncident();
      final json = SafetyEventSerializer.encodeIncidents([incident]);
      final decoded = SafetyEventSerializer.decodeIncidents(json);

      expect(decoded, hasLength(1));
      expect(decoded[0].id, equals(incident.id));
      expect(decoded[0].status, equals(incident.status));
      expect(decoded[0].events, hasLength(incident.events.length));
      expect(decoded[0].vehicleType, equals(VehicleType.taxi));
      expect(decoded[0].hasVehicleRegistration, isTrue);
    });

    test('round-trips multiple incidents', () {
      final incidents = [
        _createTestIncident(id: 'i1'),
        _createTestIncident(id: 'i2', eventTypes: [SafetyEventType.journeyStarted]),
      ];
      final json = SafetyEventSerializer.encodeIncidents(incidents);
      final decoded = SafetyEventSerializer.decodeIncidents(json);

      expect(decoded, hasLength(2));
      expect(decoded[0].id, equals('i1'));
      expect(decoded[1].id, equals('i2'));
    });

    test('preserves event metadata', () {
      final incident = SafetyIncident(
        id: 'meta_test',
        status: SafetyIncidentStatus.completed,
        createdAt: DateTime.utc(2026, 1, 1),
        events: [
          RecordedSafetyEvent(
            eventId: 'evt1',
            eventType: SafetyEventType.vehicleAttached,
            occurredAt: DateTime.utc(2026, 1, 1, 12),
            sessionId: 's1',
            metadata: {
              'vehicleType': 'taxi',
              'hasRegistration': 'true',
            },
          ),
        ],
        hashes: ['hash1'],
        genesisHash: incidentGenesisHash,
      );

      final json = SafetyEventSerializer.encodeIncidents([incident]);
      final decoded = SafetyEventSerializer.decodeIncidents(json);

      expect(decoded[0].events[0].metadata, equals({
        'vehicleType': 'taxi',
        'hasRegistration': 'true',
      }));
    });

    test('returns empty list for invalid JSON', () {
      expect(SafetyEventSerializer.decodeIncidents('not json'), isEmpty);
    });

    test('returns empty list for empty string', () {
      expect(SafetyEventSerializer.decodeIncidents(''), isEmpty);
    });

    test('handles version mismatch gracefully', () {
      final json = '{"version":99,"incidents":[]}';
      expect(SafetyEventSerializer.decodeIncidents(json), isEmpty);
    });

    test('handles missing incidents key', () {
      final json = '{"version":1}';
      expect(SafetyEventSerializer.decodeIncidents(json), isEmpty);
    });

    test('incident with no endedAt round-trips correctly', () {
      final incident = SafetyIncident(
        id: 'no_end',
        status: SafetyIncidentStatus.recording,
        createdAt: DateTime.utc(2026, 1, 1),
        events: [],
        hashes: [],
        genesisHash: incidentGenesisHash,
      );

      final json = SafetyEventSerializer.encodeIncidents([incident]);
      final decoded = SafetyEventSerializer.decodeIncidents(json);

      expect(decoded[0].endedAt, isNull);
      expect(decoded[0].status, equals(SafetyIncidentStatus.recording));
    });

    test('incident without vehicle round-trips correctly', () {
      final incident = SafetyIncident(
        id: 'no_vehicle',
        status: SafetyIncidentStatus.completed,
        createdAt: DateTime.utc(2026, 1, 1),
        events: [],
        hashes: [],
        genesisHash: incidentGenesisHash,
      );

      final json = SafetyEventSerializer.encodeIncidents([incident]);
      final decoded = SafetyEventSerializer.decodeIncidents(json);

      expect(decoded[0].vehicleType, isNull);
      expect(decoded[0].hasVehicleRegistration, isFalse);
    });
  });
}
