import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/live_location/domain/live_location_session.dart';
import 'package:guardianher/features/live_location/domain/live_share_message.dart';

void main() {
  group('LiveShareDuration', () {
    test('exposes exactly the product-mandated closed set', () {
      expect(
        LiveShareDuration.values.map((d) => d.minutes).toList(),
        [15, 30, 60, 120],
      );
    });

    test('unknown minutes fall back to the smallest safe window', () {
      expect(LiveShareDuration.fromMinutes(45), LiveShareDuration.minutes15);
      expect(LiveShareDuration.fromMinutes(-1), LiveShareDuration.minutes15);
      expect(
        LiveShareDuration.fromMinutes(30),
        LiveShareDuration.minutes30,
      );
    });
  });

  group('LiveUpdateInterval', () {
    test('normal and sos are the only cadences', () {
      expect(LiveUpdateInterval.normal.seconds, 30);
      expect(LiveUpdateInterval.sos.seconds, 10);
    });
  });

  group('LiveLocationSession', () {
    final createdAt = DateTime.utc(2026, 1, 1, 12, 0, 0);

    LiveLocationSession sessionWith(DateTime expiresAt) =>
        LiveLocationSession(
          sessionId: 'abc123',
          token: 'T' * 43,
          createdAt: createdAt,
          expiresAt: expiresAt,
          updateInterval: LiveUpdateInterval.normal,
          shareUrl: 'https://live.example.org/live/${'T' * 43}',
        );

    test('a session expiring in the future is not expired', () {
      // isExpired consults the wall clock; a far-future date is safely
      // non-expired regardless of when the test runs.
      final session = sessionWith(DateTime.now().toUtc().add(const Duration(hours: 2)));
      expect(session.isExpired, isFalse);
      expect(session.remainingTime, isNot(Duration.zero));
    });

    test('copyWith updates only lastLocationAt', () {
      final base = sessionWith(createdAt.add(const Duration(minutes: 30)));
      final captured = DateTime.utc(2026, 1, 1, 12, 0, 20);
      final updated = base.copyWith(lastLocationAt: captured);

      expect(updated.lastLocationAt, captured);
      expect(updated.sessionId, base.sessionId);
      expect(updated.token, base.token);
      expect(updated.expiresAt, base.expiresAt);
      expect(updated.shareUrl, base.shareUrl);
    });

    test('toString never contains coordinates or the token', () {
      final session = sessionWith(createdAt.add(const Duration(minutes: 30)));
      final text = session.toString();
      expect(text.contains('T' * 43), isFalse);
      expect(text.contains('latitude'), isFalse);
    });
  });

  group('buildLiveShareMessage', () {
    test('contains the URL and the local expiry time', () {
      final expiresAt = DateTime.utc(2026, 1, 1, 13, 30, 0);
      final message = buildLiveShareMessage(
        shareUrl: 'https://live.example.org/live/abc',
        expiresAt: expiresAt,
      );
      expect(message, contains('GuardianHer live location'));
      expect(message, contains('https://live.example.org/live/abc'));
      expect(message, contains(expiresAt.toLocal().hour.toString().padLeft(2, '0')));
      // The link IS the live mechanism; the channel is not.
      expect(message, isNot(contains('WhatsApp')));
      expect(message, isNot(contains('SMS')));
    });
  });

  group('buildLiveShareUrl', () {
    test('appends the token to the live path', () {
      expect(
        buildLiveShareUrl(baseUrl: 'https://live.example.org', token: 'X' * 43),
        'https://live.example.org/live/${'X' * 43}',
      );
    });
  });
}
