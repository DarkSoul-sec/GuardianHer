import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/result/result.dart';
import '../domain/live_location_failures.dart';
import '../domain/live_location_session.dart';

/// The result of a successful session creation.
@immutable
class LiveSessionCreation {
  const LiveSessionCreation({
    required this.token,
    required this.shareUrl,
    required this.expiresAt,
  });

  final String token;
  final String shareUrl;
  final DateTime expiresAt;
}

/// Talks to the GuardianHer live-location backend.
///
/// PRIVACY: requests carry coordinates ONLY on the update endpoint; nothing
/// is ever logged by this class. Failures are typed, never thrown past the
/// boundary, and their details never include tokens or URLs.
abstract interface class LiveLocationApiClient {
  /// Whether an API base URL was configured for this build.
  bool get isConfigured;

  Future<Result<LiveSessionCreation>> createSession({
    required LiveShareDuration duration,
    required LiveUpdateInterval interval,
  });

  /// Pushes the latest fix. Only ever carries THE latest fix — there is no
  /// backlog upload (§8).
  Future<Result<void>> pushLocation({
    required String token,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
  });

  /// Best-effort revoke. Returns success also when the server reports the
  /// session already ended — the outcome the caller wants either way.
  Future<Result<void>> stopSession({required String token});
}

/// Base URL injected at build time:
/// `flutter build/run --dart-define=GUARDIANHER_LIVE_API_URL=https://…`
///
/// Empty by default: no production infrastructure is hard-coded (§28), and
/// an unconfigured build shows an honest "not available in this build"
/// state instead of guessing an endpoint.
const String liveApiBaseUrl = String.fromEnvironment(
  'GUARDIANHER_LIVE_API_URL',
  defaultValue: '',
);

class HttpLiveLocationApiClient implements LiveLocationApiClient {
  HttpLiveLocationApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? liveApiBaseUrl).trim();

  final http.Client _client;

  /// Public for tests/diagnostics; contains NO secret.
  final String baseUrl;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  bool get isConfigured => baseUrl.isNotEmpty;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<Result<LiveSessionCreation>> createSession({
    required LiveShareDuration duration,
    required LiveUpdateInterval interval,
  }) async {
    if (!isConfigured) {
      return Err(LiveLocationFailure(LiveLocationFailureType.notConfigured));
    }
    try {
      final response = await _client
          .post(
            _uri('/api/v1/live-sessions'),
            headers: {'content-type': 'application/json'},
            body: '{"duration_minutes":${duration.minutes},'
                '"update_interval_seconds":${interval.seconds}}',
          )
          .timeout(_timeout);
      if (response.statusCode != 201) {
        return Err(_failureFor(response.statusCode));
      }
      final decoded = _decodeJsonMap(response.body);
      if (decoded == null) {
        return Err(
            LiveLocationFailure(LiveLocationFailureType.invalidResponse));
      }
      final token = decoded['token'];
      final shareUrl = decoded['share_url'];
      final expiresAtRaw = decoded['expires_at'];
      if (token is! String ||
          shareUrl is! String ||
          expiresAtRaw is! String ||
          token.length != 43) {
        return Err(
            LiveLocationFailure(LiveLocationFailureType.invalidResponse));
      }
      final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
      if (expiresAt == null) {
        return Err(
            LiveLocationFailure(LiveLocationFailureType.invalidResponse));
      }
      return Ok(LiveSessionCreation(
        token: token,
        shareUrl: shareUrl,
        expiresAt: expiresAt,
      ));
    } on TimeoutException {
      return Err(_transportFailure());
    } catch (_) {
      return Err(_transportFailure());
    }
  }

  @override
  Future<Result<void>> pushLocation({
    required String token,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
  }) async {
    if (!isConfigured) {
      return Err(LiveLocationFailure(LiveLocationFailureType.notConfigured));
    }
    final body =
        '{"latitude":$latitude,"longitude":$longitude,'
        '"accuracy_meters":$accuracyMeters,'
        '"captured_at":"${capturedAt.toUtc().toIso8601String()}"}';
    try {
      final response = await _client
          .post(
            _uri('/api/v1/live-sessions/$token/location'),
            headers: {'content-type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return const Ok(null);
      }
      // Expired/revoked sessions end the loop with typed failures.
      return Err(_sessionStateFailureFor(response.statusCode, response.body));
    } on TimeoutException {
      return Err(_transportFailure());
    } catch (_) {
      return Err(_transportFailure());
    }
  }

  @override
  Future<Result<void>> stopSession({required String token}) async {
    if (!isConfigured) {
      return Err(LiveLocationFailure(LiveLocationFailureType.notConfigured));
    }
    try {
      final response = await _client
          .post(
            _uri('/api/v1/live-sessions/$token/stop'),
            headers: {'content-type': 'application/json'},
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return const Ok(null);
      }
      // 404 unknown / 410 already-ended both mean "the URL is dead", which
      // is exactly what stop wants; treat as success per contract.
      if (response.statusCode == 404 || response.statusCode == 410) {
        return const Ok(null);
      }
      return Err(_failureFor(response.statusCode));
    } on TimeoutException {
      return Err(_transportFailure());
    } catch (_) {
      return Err(_transportFailure());
    }
  }

  // ---- mapping helpers ----

  LiveLocationFailure _transportFailure() =>
      LiveLocationFailure(LiveLocationFailureType.networkUnavailable);

  LiveLocationFailure _serverFailure() =>
      LiveLocationFailure(LiveLocationFailureType.serverUnavailable);

  LiveLocationFailure _failureFor(int statusCode) {
    if (statusCode == 429) {
      return LiveLocationFailure(LiveLocationFailureType.rejectedByServer);
    }
    if (statusCode >= 500) {
      return _serverFailure();
    }
    return LiveLocationFailure(LiveLocationFailureType.rejectedByServer);
  }

  LiveLocationFailure _sessionStateFailureFor(int statusCode, String body) {
    final decoded = _decodeJsonMap(body);
    final code = decoded?['error'] is Map
        ? (decoded!['error'] as Map)['code']
        : null;
    if (code == 'expired') {
      return LiveLocationFailure(LiveLocationFailureType.sessionExpired);
    }
    if (code == 'revoked') {
      return LiveLocationFailure(LiveLocationFailureType.sessionRevoked);
    }
    return _failureFor(statusCode);
  }

  static Map<String, dynamic>? _decodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
