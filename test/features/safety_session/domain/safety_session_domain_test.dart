import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/safety_session/domain/location_sharing_policy.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_id.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_type.dart';

void main() {
  group('SafetySessionId', () {
    test('generated ids are valid, 32-char lowercase hex and unique', () {
      final ids = {
        for (var i = 0; i < 200; i++) SafetySessionId.generate().value,
      };
      expect(ids.length, 200, reason: 'ids must not collide');
      for (final id in ids) {
        expect(id.length, 32);
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), isTrue);
      }
    });

    test('parse accepts canonical form and rejects everything else', () {
      final valid = SafetySessionId.generate();
      expect(SafetySessionId.tryParse(valid.value)?.value, valid.value);
      expect(SafetySessionId(valid.value).value, valid.value);

      for (final bad in [
        '',
        'short',
        'A' * 32, // uppercase rejected — canonical form only
        '${valid.value}0',
        '0x${valid.value.substring(2)}',
        '${valid.value.substring(0, 31)}g',
      ]) {
        expect(SafetySessionId.tryParse(bad), isNull);
        expect(() => SafetySessionId(bad), throwsArgumentError);
      }
    });

    test('equality is by value; toString never leaks the full id', () {
      final a = SafetySessionId.generate();
      final b = SafetySessionId.tryParse(a.value)!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final text = a.toString();
      expect(text.contains(a.value), isFalse);
      expect(text, contains(a.value.substring(0, 8)));
    });
  });

  group('LocationSharingPolicy', () {
    const policy = LocationSharingPolicy();

    test('mandated cadences (§5)', () {
      expect(policy.sosInterval, const Duration(seconds: 10));
      expect(policy.liveInterval, const Duration(seconds: 30));
      expect(
        policy.intervalFor(SafetySessionType.safeJourney),
        const Duration(seconds: 20),
      );
      expect(
        policy.intervalFor(SafetySessionType.sos),
        policy.sosInterval,
      );
    });

    test('journey cadence clamps into the closed 15–30 range', () {
      expect(
        policy.journeyInterval(requestedSeconds: 15),
        const Duration(seconds: 15),
      );
      expect(
        policy.journeyInterval(requestedSeconds: 30),
        const Duration(seconds: 30),
      );
      expect(policy.journeyInterval(requestedSeconds: 1),
          const Duration(seconds: 15));
      expect(policy.journeyInterval(requestedSeconds: 600),
          const Duration(seconds: 30));
      expect(policy.journeyInterval(), const Duration(seconds: 20));
    });
  });
}
