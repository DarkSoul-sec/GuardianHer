import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/data/call_service_impl.dart';
import 'package:guardianher/data/map_service_impl.dart';
import 'package:guardianher/data/notification_service_impl.dart';
import 'package:guardianher/data/sms_service_impl.dart';
import 'package:guardianher/features/location/domain/location_point.dart';

void main() {
  group('buildDialUri', () {
    test('opens the tel: scheme with an E.164-style + prefix', () {
      final uri = buildDialUri('15551234567');
      expect(uri.scheme, 'tel');
      expect(uri.path, '+15551234567');
      expect(uri.toString(), 'tel:+15551234567');
    });

    test('handles short emergency numbers', () {
      final uri = buildDialUri('112');
      expect(uri.toString(), 'tel:+112');
    });
  });

  group('buildSmsUri', () {
    test('targets the sms: scheme with a pre-filled body', () {
      final uri = buildSmsUri('15551234567', 'I need help.');
      expect(uri.scheme, 'sms');
      expect(uri.path, '+15551234567');
      expect(uri.queryParameters['body'], 'I need help.');
      expect(uri.toString(), 'sms:+15551234567?body=I+need+help.');
    });

    test('recipient-less sharing carries only the pre-filled body', () {
      final uri = buildSmsUri('', 'I may need help.');
      expect(uri.scheme, 'sms');
      expect(uri.path, isEmpty);
      expect(uri.queryParameters['body'], 'I may need help.');
      expect(uri.toString(), 'sms:?body=I+may+need+help.');
    });
  });

  group('buildGeoUri', () {
    test('points the geo: scheme at the exact coordinates', () {
      final uri = buildGeoUri(
        LocationPoint(
          latitude: 12.345678,
          longitude: 98.765432,
          accuracyMeters: 15,
          capturedAt: _testTime,
        ),
      );
      expect(uri.scheme, 'geo');
      expect(uri.path, '0,0');
      expect(uri.queryParameters['q'], '12.345678,98.765432');
      expect(uri.toString(), 'geo:0,0?q=12.345678,98.765432');
    });
  });

  group('notification constants', () {
    test('the SOS notification id is stable and unique', () {
      expect(sosNotificationId, 1001);
    });

    test('the SOS channel is dedicated and named', () {
      expect(sosNotificationChannelId, 'sos_alert');
      expect(sosNotificationChannelName, 'SOS alerts');
    });

    test('notification content is generic and reveals no personal data', () {
      expect(sosActiveNotificationTitle, 'SOS ACTIVE');
      expect(sosActiveNotificationBody,
          'Open GuardianHer to manage your SOS.');
      expect(sosStoppingNotificationTitle, 'SOS');
      expect(sosStoppingNotificationBody, 'Stopping SOS…');
      // Guard against a future regression that embeds names, numbers or
      // locations into the notification copy.
      for (final text in [
        sosActiveNotificationTitle,
        sosActiveNotificationBody,
        sosStoppingNotificationTitle,
        sosStoppingNotificationBody,
      ]) {
        expect(text.contains(RegExp(r'\d{4,}')), isFalse,
            reason: 'notification copy must not embed digits');
      }
    });
  });
}

final _testTime = DateTime.utc(2026, 1, 1, 12);