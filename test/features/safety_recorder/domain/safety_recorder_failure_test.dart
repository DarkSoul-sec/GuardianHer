import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/safety_recorder/domain/safety_recorder_failure.dart';

void main() {
  group('SafetyRecorderFailure', () {
    test('BufferOverflowFailure has correct code', () {
      const failure = BufferOverflowFailure();
      expect(failure.code, 'buffer_overflow');
      expect(failure.message, isNotEmpty);
    });

    test('CorruptedIncidentDataFailure has correct code', () {
      const failure = CorruptedIncidentDataFailure();
      expect(failure.code, 'corrupted_incident_data');
      expect(failure.message, isNotEmpty);
    });

    test('UnsupportedStorageVersionFailure has correct code', () {
      const failure = UnsupportedStorageVersionFailure();
      expect(failure.code, 'unsupported_storage_version');
      expect(failure.message, isNotEmpty);
    });

    test('IntegrityVerificationFailure has correct code', () {
      const failure = IntegrityVerificationFailure();
      expect(failure.code, 'integrity_verification');
      expect(failure.message, isNotEmpty);
    });

    test('IncidentRetentionLimitFailure has correct code', () {
      const failure = IncidentRetentionLimitFailure();
      expect(failure.code, 'incident_retention_limit');
      expect(failure.message, isNotEmpty);
    });

    test('all failures accept custom messages', () {
      const msg = 'custom error message';
      expect(BufferOverflowFailure(msg).message, msg);
      expect(CorruptedIncidentDataFailure(msg).message, msg);
      expect(UnsupportedStorageVersionFailure(msg).message, msg);
      expect(IntegrityVerificationFailure(msg).message, msg);
      expect(IncidentRetentionLimitFailure(msg).message, msg);
    });

    test('all failures are subtypes of SafetyRecorderFailure', () {
      expect(BufferOverflowFailure(), isA<SafetyRecorderFailure>());
      expect(CorruptedIncidentDataFailure(), isA<SafetyRecorderFailure>());
      expect(UnsupportedStorageVersionFailure(), isA<SafetyRecorderFailure>());
      expect(IntegrityVerificationFailure(), isA<SafetyRecorderFailure>());
      expect(IncidentRetentionLimitFailure(), isA<SafetyRecorderFailure>());
    });
  });
}
