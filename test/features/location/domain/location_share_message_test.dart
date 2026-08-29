import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/location/domain/location_point.dart';
import 'package:guardianher/features/location/domain/location_share_message.dart';

final _point = LocationPoint(
  latitude: 12.345678,
  longitude: 98.765432,
  accuracyMeters: 15,
  capturedAt: DateTime.utc(2026, 1, 1, 12),
);

void main() {
  group('buildMapsShareUrl', () {
    test('builds a tappable web-Maps link from the coordinates', () {
      expect(
        buildMapsShareUrl(_point),
        'https://maps.google.com/?q=12.345678,98.765432',
      );
    });
  });

  group('buildLocationShareMessage', () {
    test('announces the SOS alert and embeds the location link', () {
      final message = buildLocationShareMessage(_point);
      expect(message, contains('GuardianHer SOS alert'));
      expect(message, contains('Current location captured at'));
      expect(message, isNot(contains('Last known')));
      expect(message, contains('https://maps.google.com/?q=12.345678,98.765432'));
    });

    test('labels a cached fallback as last known, never current', () {
      final stale = LocationPoint(
        latitude: 12.345678,
        longitude: 98.765432,
        accuracyMeters: 15,
        capturedAt: DateTime.utc(2026, 1, 1, 12),
        isStale: true,
      );
      final message = buildLocationShareMessage(stale);
      expect(message, contains('Last known location captured at'));
      expect(message, isNot(contains('Current location captured at')));
    });
  });
}
