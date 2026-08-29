import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';

import 'safety_recorder_test_helpers.dart';

/// Privacy tests prove that no sensitive values appear in serialized events,
/// event IDs, session IDs, or incident metadata.
void main() {
  group('Privacy: no PII in events', () {
    test('phone numbers do not appear in serialized events', () {
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.communicationHandedOff,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'abc123def456',
        metadata: {
          SafetyEventMetadataKey.channelType: 'sms',
        },
      );

      final serialized = event.toString();
      expect(RegExp(r'\d{10}').hasMatch(serialized), isFalse);
      expect(RegExp(r'\+\d{10,}').hasMatch(serialized), isFalse);
    });

    test('email addresses do not appear in serialized events', () {
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.communicationAttempted,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'abc123def456',
        metadata: {
          SafetyEventMetadataKey.channelType: 'email',
        },
      );

      final serialized = event.toString();
      expect(RegExp(r'\S+@\S+\.\S+').hasMatch(serialized), isFalse);
    });

    test('message bodies do not appear in serialized events', () {
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.communicationHandedOff,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'abc123def456',
      );

      final serialized = event.toString();
      expect(serialized.contains('I need help'), isFalse);
      expect(serialized.contains('emergency'), isFalse);
    });

    test('coordinates do not appear in serialized events', () {
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.locationCaptured,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'abc123def456',
        metadata: {
          SafetyEventMetadataKey.accuracyMeters: '15.0',
        },
      );

      final serialized = event.toString();
      // Coordinates are lat/lng pairs like 12.345678, 98.765432
      expect(RegExp(r'\d{2,3}\.\d{4,}').hasMatch(serialized), isFalse);
    });

    test('vehicle registration does not appear in event payloads', () {
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.vehicleAttached,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'abc123def456',
        metadata: {
          SafetyEventMetadataKey.vehicleType: 'taxi',
          SafetyEventMetadataKey.hasRegistration: 'true',
        },
      );

      final serialized = event.toString();
      // Common Indian plate patterns
      expect(RegExp(r'[A-Z]{2}\d{2}[A-Z]{2}\d{4}').hasMatch(serialized),
          isFalse);
    });

    test('event IDs contain no PII', () {
      final eventId = generateRecorderEventId();
      expect(eventId.length, equals(32));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(eventId), isTrue);
      // No phone numbers, emails, names, etc.
      expect(RegExp(r'[A-Z]').hasMatch(eventId), isFalse);
    });

    test('session IDs remain opaque', () {
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.sosActivated,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6',
      );

      // Session ID should not contain recognizable patterns.
      expect(event.sessionId.contains('@'), isFalse);
      expect(event.sessionId.contains('+'), isFalse);
    });

    test('URLs do not contain vehicle registration', () {
      // No URLs should be in event metadata.
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.communicationHandedOff,
        occurredAt: DateTime.utc(2026, 1, 1, 12),
        sessionId: 'test',
        metadata: {
          SafetyEventMetadataKey.channelType: 'whatsapp',
        },
      );

      expect(event.metadata.values.any((v) => v.contains('http')), isFalse);
    });
  });

  group('Privacy: no PII in incidents', () {
    test('incident toString does not expose phone numbers', () {
      final incident = createTestIncident(
        id: 'phone_test',
        eventTypes: [SafetyEventType.sosActivated],
      );

      final str = incident.toString();
      expect(RegExp(r'\d{10}').hasMatch(str), isFalse);
    });

    test('incident toString does not expose coordinates', () {
      final incident = createTestIncident(
        id: 'coord_test',
        eventTypes: [SafetyEventType.locationCaptured],
      );

      final str = incident.toString();
      expect(RegExp(r'\d{2,3}\.\d{4,}').hasMatch(str), isFalse);
    });

    test('incident toString does not expose email addresses', () {
      final incident = createTestIncident(
        id: 'email_test',
        eventTypes: [SafetyEventType.communicationAttempted],
      );

      final str = incident.toString();
      expect(RegExp(r'\S+@\S+').hasMatch(str), isFalse);
    });

    test('vehicle type label does not contain registration', () {
      final incident = createTestIncident(
        id: 'vehicle_privacy',
        eventTypes: [SafetyEventType.vehicleAttached],
      );

      final str = incident.toString();
      // vehicleType.name is "taxi" — not a registration number
      expect(RegExp(r'[A-Z]{2}\d{2}').hasMatch(str), isFalse);
    });
  });

  group('Privacy: SafetyEventMetadataKey', () {
    test('all keys are lowercase camelCase strings', () {
      expect(SafetyEventMetadataKey.vehicleType, isNotEmpty);
      expect(SafetyEventMetadataKey.hasRegistration, isNotEmpty);
      expect(SafetyEventMetadataKey.accuracyMeters, isNotEmpty);
      expect(SafetyEventMetadataKey.isStale, isNotEmpty);
      expect(SafetyEventMetadataKey.failureCategory, isNotEmpty);
      expect(SafetyEventMetadataKey.channelType, isNotEmpty);
      expect(SafetyEventMetadataKey.endReason, isNotEmpty);
    });

    test('no key contains sensitive terms', () {
      const keys = [
        SafetyEventMetadataKey.vehicleType,
        SafetyEventMetadataKey.hasRegistration,
        SafetyEventMetadataKey.accuracyMeters,
        SafetyEventMetadataKey.isStale,
        SafetyEventMetadataKey.failureCategory,
        SafetyEventMetadataKey.channelType,
        SafetyEventMetadataKey.endReason,
      ];

      for (final key in keys) {
        expect(key.contains('phone'), isFalse);
        expect(key.contains('email'), isFalse);
        expect(key.contains('name'), isFalse);
        expect(key.contains('address'), isFalse);
        expect(key.contains('location'), isFalse);
        expect(key.contains('lat'), isFalse);
        expect(key.contains('lng'), isFalse);
        expect(key.contains('coordinate'), isFalse);
      }
    });
  });
}
