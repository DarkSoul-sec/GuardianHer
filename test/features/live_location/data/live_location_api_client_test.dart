import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guardianher/features/live_location/data/live_location_api_client.dart';
import 'package:guardianher/features/live_location/domain/live_location_failures.dart';
import 'package:guardianher/features/live_location/domain/live_location_session.dart';

void main() {
  const base = 'https://live.example.org';

  HttpLiveLocationApiClient clientWith(MockClientHandler handler) {
    return HttpLiveLocationApiClient(
      client: MockClient(handler),
      baseUrl: base,
    );
  }

  final goodCreation = jsonEncode({
    'token': 'T' * 43,
    'share_url': '$base/live/${'T' * 43}',
    'expires_at': '2026-01-01T12:30:00+00:00',
    'update_interval_seconds': 30,
  });

  group('unconfigured builds', () {
    test('report notConfigured without issuing any request', () async {
      var requests = 0;
      final client = HttpLiveLocationApiClient(
        client: MockClient((_) async {
          requests++;
          throw StateError('must not be called');
        }),
        baseUrl: '',
      );
      expect(client.isConfigured, isFalse);

      final created = await client.createSession(
        duration: LiveShareDuration.minutes30,
        interval: LiveUpdateInterval.normal,
      );
      expect(created.isErr, isTrue);

      final pushed = await client.pushLocation(
        token: 'T' * 43,
        latitude: 1,
        longitude: 2,
        accuracyMeters: 3,
        capturedAt: DateTime.now().toUtc(),
      );
      expect(pushed.isErr, isTrue);

      final stopped = await client.stopSession(token: 'T' * 43);
      expect(stopped.isErr, isTrue);
      expect(requests, 0);
    });
  });

  group('createSession', () {
    test('parses token, share URL and expiry on 201', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return http.Response(goodCreation, 201);
      });

      final result = await client.createSession(
        duration: LiveShareDuration.minutes30,
        interval: LiveUpdateInterval.normal,
      );

      result.fold(
        (creation) {
          expect(creation.token, 'T' * 43);
          expect(creation.shareUrl, '$base/live/${'T' * 43}');
          expect(creation.expiresAt.year, 2026);
        },
        (_) => fail('expected success'),
      );
      expect(captured.url.toString(), '$base/api/v1/live-sessions');
      expect(captured.method, 'POST');
      expect(captured.body, contains('"duration_minutes":30'));
      expect(captured.body, contains('"update_interval_seconds":30'));
    });

    test('rate limit maps to rejectedByServer', () async {
      final client = clientWith((_) async => http.Response('{"error":{}}', 429));
      final result = await client.createSession(
        duration: LiveShareDuration.minutes15,
        interval: LiveUpdateInterval.normal,
      );
      expect(result.isErr, isTrue);
      // The typed failure is carried inside Err; assert via fold.
      var type = LiveLocationFailureType.serverUnavailable;
      result.fold((_) {}, (failure) {
        failure as LiveLocationFailure;
        type = failure.type;
      });
      expect(type, LiveLocationFailureType.rejectedByServer);
    });

    test('server errors map to serverUnavailable', () async {
      final client = clientWith((_) async => http.Response('boom', 500));
      final result = await client.createSession(
        duration: LiveShareDuration.minutes15,
        interval: LiveUpdateInterval.sos,
      );
      var type = LiveLocationFailureType.rejectedByServer;
      result.fold((_) {}, (failure) {
        failure as LiveLocationFailure;
        type = failure.type;
      });
      expect(type, LiveLocationFailureType.serverUnavailable);
    });

    test('malformed JSON maps to invalidResponse', () async {
      final client = clientWith((_) async => http.Response('<html>', 201));
      final result = await client.createSession(
        duration: LiveShareDuration.minutes15,
        interval: LiveUpdateInterval.normal,
      );
      var type = LiveLocationFailureType.networkUnavailable;
      result.fold((_) {}, (failure) {
        failure as LiveLocationFailure;
        type = failure.type;
      });
      expect(type, LiveLocationFailureType.invalidResponse);
    });

    test('a short token is rejected as invalidResponse', () async {
      final client = clientWith(
        (_) async => http.Response(
          jsonEncode({'token': 'short', 'share_url': 'x', 'expires_at': 'y'}),
          201,
        ),
      );
      final result = await client.createSession(
        duration: LiveShareDuration.minutes15,
        interval: LiveUpdateInterval.normal,
      );
      expect(result.isErr, isTrue);
    });
  });

  group('pushLocation', () {
    Future<({LiveLocationFailureType? type})> pushWith(
      MockClientHandler handler,
    ) async {
      final client = clientWith(handler);
      final result = await client.pushLocation(
        token: 'T' * 43,
        latitude: 12.345678,
        longitude: 98.765432,
        accuracyMeters: 18,
        capturedAt: DateTime.utc(2026, 1, 1, 12),
      );
      LiveLocationFailureType? type;
      result.fold(
        (_) {},
        (failure) => type = (failure as LiveLocationFailure).type,
      );
      return (type: type);
    }

    test('sends the fix with an ISO UTC timestamp', () async {
      late http.Request captured;
      final outcome = await pushWith((request) async {
        captured = request;
        return http.Response('{"ok":true}', 200);
      });
      expect(outcome.type, isNull);
      expect(captured.url.path, '/api/v1/live-sessions/${'T' * 43}/location');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['captured_at'], endsWith('Z'));
      expect(body['latitude'], closeTo(12.345678, 1e-9));
    });

    test('expired and revoked map to their typed failures', () async {
      final expired = await pushWith(
        (_) async => http.Response('{"error":{"code":"expired"}}', 410),
      );
      expect(expired.type, LiveLocationFailureType.sessionExpired);

      final revoked = await pushWith(
        (_) async => http.Response('{"error":{"code":"revoked"}}', 410),
      );
      expect(revoked.type, LiveLocationFailureType.sessionRevoked);
    });

    test('connection refused maps to networkUnavailable', () async {
      final outcome = await pushWith((request) async {
        throw http.ClientException('offline');
      });
      expect(outcome.type, LiveLocationFailureType.networkUnavailable);
    });
  });

  group('stopSession', () {
    test('treats already-ended sessions as success', () async {
      for (final status in [200, 404, 410]) {
        final client = clientWith((_) async => http.Response('{}', status));
        final result = await client.stopSession(token: 'T' * 43);
        expect(result.isOk, isTrue, reason: 'status $status must succeed');
      }
    });

    test('unexpected server failure stays an error', () async {
      final client = clientWith((_) async => http.Response('{}', 503));
      final result = await client.stopSession(token: 'T' * 43);
      expect(result.isErr, isTrue);
    });
  });
}
