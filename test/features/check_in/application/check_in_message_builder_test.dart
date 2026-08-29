import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/check_in/application/check_in_message_builder.dart';
import 'package:guardianher/features/location/domain/location_point.dart';

void main() {
  final point = LocationPoint(
    latitude: 12.345678,
    longitude: 98.765432,
    accuracyMeters: 15,
    capturedAt: DateTime.utc(2026, 1, 1, 12),
  );

  test('includes the maps link when a fix is available', () {
    final body = buildCheckInMessageBody(point: point, missedCount: 0);
    expect(body, contains('https://maps.google.com/?q=12.345678,98.765432'));
    expect(body, contains('Safety check-in'));
  });

  test('says location is unavailable instead of omitting it silently', () {
    final body = buildCheckInMessageBody(point: null, missedCount: 0);
    expect(body, contains('I could not share my location right now.'));
    expect(body, isNot(contains('maps.google.com')));
  });

  test('escalates urgency when check-ins were missed', () {
    final body = buildCheckInMessageBody(point: point, missedCount: 2);
    expect(body, startsWith('I missed my previous check-in(s). '));
    expect(body, contains('maps.google.com'));
  });

  test('no escalation wording when nothing was missed', () {
    final body = buildCheckInMessageBody(point: point, missedCount: 0);
    expect(body, isNot(contains('I missed my previous')));
  });

  test('labels a stale fallback as LAST KNOWN with its capture time', () {
    final stale = LocationPoint(
      latitude: 12.345678,
      longitude: 98.765432,
      accuracyMeters: 40,
      capturedAt: DateTime.utc(2026, 1, 1, 10),
      isStale: true,
    );
    final body = buildCheckInMessageBody(point: stale, missedCount: 0);
    expect(body, contains('LAST KNOWN location'));
    expect(body, contains('2026-01-01T10:00:00.000Z'));
    expect(body, contains('maps.google.com'));
  });

  test('a fresh fix never carries the LAST KNOWN label', () {
    final body = buildCheckInMessageBody(point: point, missedCount: 0);
    expect(body, isNot(contains('LAST KNOWN')));
  });
}