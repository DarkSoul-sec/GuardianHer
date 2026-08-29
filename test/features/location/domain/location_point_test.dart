import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/location/domain/location_point.dart';

final _testTime = DateTime.utc(2026, 1, 1, 12);

void main() {
  group('LocationPoint', () {
    test('valid coordinates and accuracy are accepted', () {
      final point = LocationPoint(
        latitude: 12.345678,
        longitude: 98.765432,
        accuracyMeters: 15,
        capturedAt: _testTime,
      );
      expect(point.isValid, isTrue);
    });

    test('a negative accuracy is rejected', () {
      final point = LocationPoint(
        latitude: 12.345678,
        longitude: 98.765432,
        accuracyMeters: -1,
        capturedAt: _testTime,
      );
      expect(point.isValid, isFalse);
    });

    test('an out-of-range latitude is rejected', () {
      final point = LocationPoint(
        latitude: 91,
        longitude: 0,
        accuracyMeters: 0,
        capturedAt: _testTime,
      );
      expect(point.isValid, isFalse);
    });

    test('an out-of-range longitude is rejected', () {
      final point = LocationPoint(
        latitude: 0,
        longitude: 181,
        accuracyMeters: 0,
        capturedAt: _testTime,
      );
      expect(point.isValid, isFalse);
    });

    test('the boundary values are valid', () {
      final point = LocationPoint(
        latitude: 90,
        longitude: -180,
        accuracyMeters: 0,
        capturedAt: _testTime,
      );
      expect(point.isValid, isTrue);
    });

    test('equality compares every field', () {
      final a = LocationPoint(
        latitude: 1,
        longitude: 2,
        accuracyMeters: 3,
        capturedAt: _testTime,
      );
      final b = LocationPoint(
        latitude: 1,
        longitude: 2,
        accuracyMeters: 4,
        capturedAt: _testTime,
      );
      expect(a, isNot(equals(b)));
      expect(
        a,
        equals(LocationPoint(
          latitude: 1,
          longitude: 2,
          accuracyMeters: 3,
          capturedAt: _testTime,
        )),
      );
    });

    test('toString does not expose coordinates', () {
      final point = LocationPoint(
        latitude: 37.421999,
        longitude: -122.084057,
        accuracyMeters: 15,
        capturedAt: _testTime,
      );
      final str = point.toString();
      expect(str, isNot(contains('37.42')));
      expect(str, isNot(contains('-122.08')));
      expect(str, contains('±15m'));
    });

    test('toString shows stale flag when stale', () {
      final point = LocationPoint(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 10,
        capturedAt: _testTime,
        isStale: true,
      );
      expect(point.toString(), contains('stale'));
    });

    test('toString omits stale flag when fresh', () {
      final point = LocationPoint(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 10,
        capturedAt: _testTime,
      );
      expect(point.toString(), isNot(contains('stale')));
    });
  });
}
