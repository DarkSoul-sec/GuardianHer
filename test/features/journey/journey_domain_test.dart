import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/features/journey/domain/journey_state.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/journey/domain/vehicle_registration.dart';
import 'package:guardianher/features/safety_session/domain/safety_session.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_id.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_type.dart';

SafetySession _session() => SafetySession.start(
      id: SafetySessionId.generate(),
      type: SafetySessionType.safeJourney,
      startedAt: DateTime.utc(2026, 1, 1, 12),
    );

void main() {
  group('VehicleType', () {
    test('labels are friendly and never enum names', () {
      expect(VehicleType.auto.label, 'Auto');
      expect(VehicleType.taxi.label, 'Taxi');
      expect(VehicleType.cab.label, 'Cab');
      expect(VehicleType.bus.label, 'Bus');
      expect(VehicleType.privateVehicle.label, 'Private Vehicle');
      expect(VehicleType.other.label, 'Other');
      for (final type in VehicleType.values) {
        expect(type.label, isNot(type.name));
      }
    });
  });

  group('Registration normalization', () {
    test('spacing, hyphens and case all resolve to one canonical value', () {
      const inputs = [
        'DL 01 AB 1234',
        'DL01AB1234',
        'dl-01-ab-1234',
        'dl 01 ab 1234',
        'DL-01-AB-1234',
        ' dl01ab1234 ',
        'DL.01.AB.1234',
      ];
      final canonicals = inputs.map((raw) {
        final result = normalizeRegistration(raw);
        expect(result, isA<RegistrationValid>(), reason: raw);
        return (result as RegistrationValid).canonical;
      });
      expect(canonicals.toSet(), {'DL01AB1234'});
    });

    test('single-digit district series is a legitimate Indian format', () {
      final result = normalizeRegistration('MH 1 AB 1234');
      expect(
        (result as RegistrationValid).canonical,
        'MH1AB1234',
      );
      expect(formatRegistration('MH1AB1234'), 'MH 1 AB 1234');
    });

    test('BH-series registrations are recognized without reshaping', () {
      final result = normalizeRegistration('22 bh 1234 ab');
      expect((result as RegistrationValid).canonical, '22BH1234AB');
      expect(formatRegistration('22BH1234AB'), '22 BH 1234 AB');
    });

    test('foreign plates pass through WITHOUT being forced into Indian form',
        () {
      // Plausible non-Indian plate: not rewritten, just case/separator noise
      // removed. Display shows it unchanged.
      final result = normalizeRegistration('abc 123');
      expect((result as RegistrationValid).canonical, 'ABC123');
      expect(formatRegistration('ABC123'), 'ABC123');
    });

    test('empty input is rejected with the empty key', () {
      for (final raw in ['', '   ', null]) {
        final result = normalizeRegistration(raw);
        expect((result as RegistrationInvalid).reasonKey, 'empty');
      }
    });

    test('absurd length is rejected instead of silently stored', () {
      final result = normalizeRegistration('DL01AB1234EXTRAORDINAIRE');
      expect((result as RegistrationInvalid).reasonKey, 'tooLong');
    });

    test('junk characters are rejected with a stable key', () {
      final result = normalizeRegistration('DL##12@@');
      expect((result as RegistrationInvalid).reasonKey, 'invalidCharacters');
    });

    test('formatting round-trips every classic shape', () {
      for (final canonical in ['DL01AB1234', 'KA05MK4532', 'MH12AB1234']) {
        final spaced = formatRegistration(canonical);
        final again = normalizeRegistration(spaced);
        expect((again as RegistrationValid).canonical, canonical,
            reason: '$canonical -> $spaced -> ?');
      }
    });
  });

  group('VehicleInfo', () {
    test('creation with every field; optional fields stay optional', () {
      const minimal = VehicleInfo(type: VehicleType.taxi);
      expect(minimal.hasRegistration, isFalse);
      expect(minimal.driverName, isNull);
      expect(minimal.bookingReference, isNull);

      const full = VehicleInfo(
        type: VehicleType.taxi,
        registrationNumber: 'DL01AB1234',
        driverName: 'Ramesh',
        bookingReference: 'UB-771234',
      );
      expect(full.hasRegistration, isTrue);
      expect(full.displayRegistrationNumber, 'DL 01 AB 1234');
    });

    test('toString never leaks registration, driver or booking values', () {
      const vehicle = VehicleInfo(
        type: VehicleType.cab,
        registrationNumber: 'DL01AB1234',
        driverName: 'Ramesh Kumar',
        bookingReference: 'UB-771234',
      );
      final text = vehicle.toString();
      expect(text, contains('provided'));
      expect(text.contains('DL'), isFalse);
      expect(text.contains('Ramesh'), isFalse);
      expect(text.contains('UB-771234'), isFalse);
    });

    test('equality compares normalized content', () {
      expect(
        const VehicleInfo(type: VehicleType.auto),
        const VehicleInfo(type: VehicleType.auto),
      );
    });
  });

  group('JourneyState vehicle lifecycle', () {
    test('isActiveLike covers only starting and active', () {
      expect(JourneyStarting(session: _session()).isActiveLike, isTrue);
      expect(const JourneyIdle().isActiveLike, isFalse);
      expect(
        JourneyCompleted(
          reason: JourneyEndReason.arrived,
          endedAt: DateTime.utc(2026, 1, 1, 13),
          startedAt: _session().startedAt,
        ).isActiveLike,
        isFalse,
      );
    });

    test('JourneyCompleted carries the session-scoped vehicle snapshot', () {
      const vehicle = VehicleInfo(
        type: VehicleType.bus,
        registrationNumber: 'DL01AB1234',
      );
      final startedAt = DateTime.utc(2026, 1, 1, 18, 32);
      final endedAt = DateTime.utc(2026, 1, 1, 19, 4);
      final completed = JourneyCompleted(
        reason: JourneyEndReason.arrived,
        endedAt: endedAt,
        startedAt: startedAt,
        vehicle: vehicle,
      );
      expect(completed.startedAt, startedAt);
      expect(completed.vehicle?.displayRegistrationNumber, 'DL 01 AB 1234');
    });
  });

  group('Safety Recorder seam (Phase E contract, frozen in D)', () {
    test('RecordedSafetyEvent for vehicle carries category and presence — never data',
        () {
      const vehicle = VehicleInfo(
        type: VehicleType.taxi,
        registrationNumber: 'DL01AB1234',
        driverName: 'Ramesh',
      );
      final session = _session();
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.vehicleAttached,
        occurredAt: DateTime.utc(2026, 1, 1, 12, 30),
        sessionId: session.id.value,
        metadata: {
          SafetyEventMetadataKey.vehicleType: vehicle.type.name,
          SafetyEventMetadataKey.hasRegistration:
              vehicle.hasRegistration.toString(),
        },
      );

      expect(event.eventType, SafetyEventType.vehicleAttached);
      expect(event.metadata[SafetyEventMetadataKey.vehicleType], 'taxi');
      expect(event.metadata[SafetyEventMetadataKey.hasRegistration], 'true');
      expect(event.sessionId, session.id.value);
      final text = event.toString();
      expect(text.contains('DL01AB1234'), isFalse);
      expect(text.contains('Ramesh'), isFalse);
    });

    test('an unnumbered vehicle reports hasRegistration false', () {
      const vehicle = VehicleInfo(type: VehicleType.other);
      final event = RecordedSafetyEvent(
        eventId: generateRecorderEventId(),
        eventType: SafetyEventType.vehicleAttached,
        occurredAt: DateTime.now(),
        sessionId: _session().id.value,
        metadata: {
          SafetyEventMetadataKey.vehicleType: vehicle.type.name,
          SafetyEventMetadataKey.hasRegistration:
              vehicle.hasRegistration.toString(),
        },
      );
      expect(event.metadata[SafetyEventMetadataKey.hasRegistration], 'false');
    });
  });
}
