import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/safety_recorder/domain/incident_integrity.dart';

void main() {
  group('computeIncidentHash', () {
    test('produces consistent hash for same input', () {
      final event = RecordedSafetyEvent(
        eventId: 'abc123',
        eventType: SafetyEventType.sosActivated,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'session123',
      );

      final hash1 = computeIncidentHash(
        previousHash: incidentGenesisHash,
        event: event,
      );
      final hash2 = computeIncidentHash(
        previousHash: incidentGenesisHash,
        event: event,
      );

      expect(hash1, equals(hash2));
    });

    test('produces different hash for different events', () {
      final event1 = RecordedSafetyEvent(
        eventId: 'abc123',
        eventType: SafetyEventType.sosActivated,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'session123',
      );
      final event2 = RecordedSafetyEvent(
        eventId: 'def456',
        eventType: SafetyEventType.sosCompleted,
        occurredAt: DateTime.utc(2026, 1, 1, 13),
        sessionId: 'session123',
      );

      final hash1 = computeIncidentHash(
        previousHash: incidentGenesisHash,
        event: event1,
      );
      final hash2 = computeIncidentHash(
        previousHash: incidentGenesisHash,
        event: event2,
      );

      expect(hash1, isNot(equals(hash2)));
    });

    test('produces different hash for different previous hash', () {
      final event = RecordedSafetyEvent(
        eventId: 'abc123',
        eventType: SafetyEventType.sosActivated,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'session123',
      );

      final hash1 = computeIncidentHash(
        previousHash: incidentGenesisHash,
        event: event,
      );
      final hash2 = computeIncidentHash(
        previousHash: 'some-other-hash',
        event: event,
      );

      expect(hash1, isNot(equals(hash2)));
    });

    test('hash is 64 hex characters (SHA-256)', () {
      final event = RecordedSafetyEvent(
        eventId: 'abc123',
        eventType: SafetyEventType.sosActivated,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'session123',
      );

      final hash = computeIncidentHash(
        previousHash: incidentGenesisHash,
        event: event,
      );

      expect(hash.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });
  });

  group('verifyIncidentIntegrity', () {
    test('returns true for a valid chain', () {
      final events = [
        RecordedSafetyEvent(
          eventId: 'evt1',
          eventType: SafetyEventType.sosActivated,
          occurredAt: DateTime.utc(2026, 1, 1, 12),
          sessionId: 'session1',
        ),
        RecordedSafetyEvent(
          eventId: 'evt2',
          eventType: SafetyEventType.locationCaptured,
          occurredAt: DateTime.utc(2026, 1, 1, 12, 1),
          sessionId: 'session1',
        ),
      ];

      final hashes = <String>[];
      var prev = incidentGenesisHash;
      for (final event in events) {
        final hash = computeIncidentHash(
          previousHash: prev,
          event: event,
        );
        hashes.add(hash);
        prev = hash;
      }

      expect(
        verifyIncidentIntegrity(
          genesisHash: incidentGenesisHash,
          events: events,
          hashes: hashes,
        ),
        isTrue,
      );
    });

    test('returns false when hash is tampered', () {
      final events = [
        RecordedSafetyEvent(
          eventId: 'evt1',
          eventType: SafetyEventType.sosActivated,
          occurredAt: DateTime.utc(2026, 1, 1, 12),
          sessionId: 'session1',
        ),
      ];

      final hashes = [
        computeIncidentHash(
          previousHash: incidentGenesisHash,
          event: events[0],
        ),
      ];

      // Tamper with the hash.
      hashes[0] = 'tampered';

      expect(
        verifyIncidentIntegrity(
          genesisHash: incidentGenesisHash,
          events: events,
          hashes: hashes,
        ),
        isFalse,
      );
    });

    test('returns false when events and hashes length mismatch', () {
      final events = [
        RecordedSafetyEvent(
          eventId: 'evt1',
          eventType: SafetyEventType.sosActivated,
          occurredAt: DateTime.utc(2026, 1, 1, 12),
          sessionId: 'session1',
        ),
      ];

      expect(
        verifyIncidentIntegrity(
          genesisHash: incidentGenesisHash,
          events: events,
          hashes: [],
        ),
        isFalse,
      );
    });

    test('returns false for empty events', () {
      expect(
        verifyIncidentIntegrity(
          genesisHash: incidentGenesisHash,
          events: [],
          hashes: [],
        ),
        isFalse,
      );
    });
  });

  group('genesis hash', () {
    test('is a non-empty string', () {
      expect(incidentGenesisHash, isNotEmpty);
    });

    test('starts with expected prefix', () {
      expect(incidentGenesisHash, startsWith('guardianher-recorder'));
    });
  });
}
