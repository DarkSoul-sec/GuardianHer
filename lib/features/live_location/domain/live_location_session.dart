import 'package:flutter/foundation.dart';

/// Status of the live-location sharing lifecycle (Phase 3J §1).
enum LiveSessionStatus {
  /// No session; the feature is dormant.
  idle,

  /// Session creation in flight (backend + service + engine start-up).
  starting,

  /// Sharing is live: capture + upload loop running.
  active,

  /// Stop requested; teardown in flight.
  stopping,

  /// Ended because the user pressed stop.
  stopped,

  /// Ended because the server-side TTL elapsed.
  expired,

  /// Could not start (unconfigured backend, permission refusal, ...).
  failed,
}

/// The CLOSED product-mandated set of share durations (§3), in minutes.
///
/// Mirrors `CheckInInterval`: unknown values must never leak in from storage
/// or the network — there is no persistence here, but the API contract and
/// UI chips are generated from this list so client and backend agree.
enum LiveShareDuration {
  minutes15(15),
  minutes30(30),
  minutes60(60),
  minutes120(120);

  const LiveShareDuration(this.minutes);

  final int minutes;

  Duration get asDuration => Duration(minutes: minutes);

  static LiveShareDuration fromMinutes(int minutes) {
    for (final value in LiveShareDuration.values) {
      if (value.minutes == minutes) return value;
    }
    // Unknown durations fall back to the smallest safe window.
    return LiveShareDuration.minutes15;
  }
}

/// Update cadences (§4). NORMAL is the user-facing default; SOS uses the
/// faster emergency cadence. Nothing else is allowed.
enum LiveUpdateInterval {
  normal(30),
  sos(10);

  const LiveUpdateInterval(this.seconds);

  final int seconds;

  Duration get asDuration => Duration(seconds: seconds);
}

/// An immutable snapshot of a live-sharing session.
///
/// PRIVACY: holds NO coordinates, no contact data, no phone numbers. The
/// access [token] lives here only while the session runs, in memory only —
/// it is never written to preferences, logs or storage.
@immutable
class LiveLocationSession {
  const LiveLocationSession({
    required this.sessionId,
    required this.token,
    required this.createdAt,
    required this.expiresAt,
    required this.updateInterval,
    required this.shareUrl,
    this.lastLocationAt,
  });

  /// Local-only identifier for UI bookkeeping (a random UUID). Never sent to
  /// the backend; the server knows sessions by the token digest alone.
  final String sessionId;

  /// Bearer secret returned once by the backend at creation.
  final String token;

  final DateTime createdAt;
  final DateTime expiresAt;
  final LiveUpdateInterval updateInterval;

  /// The ONE link the user shares. Contains the random token — nothing else.
  final String shareUrl;

  /// When the last fix was CAPTURED locally (not necessarily uploaded).
  final DateTime? lastLocationAt;

  bool get isExpired =>
      DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  Duration get remainingTime {
    final remaining = expiresAt.toUtc().difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  LiveLocationSession copyWith({DateTime? lastLocationAt}) {
    return LiveLocationSession(
      sessionId: sessionId,
      token: token,
      createdAt: createdAt,
      expiresAt: expiresAt,
      updateInterval: updateInterval,
      shareUrl: shareUrl,
      lastLocationAt: lastLocationAt ?? this.lastLocationAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveLocationSession &&
      other.sessionId == sessionId &&
      other.token == token &&
      other.createdAt == createdAt &&
      other.expiresAt == expiresAt &&
      other.updateInterval == updateInterval &&
      other.shareUrl == shareUrl &&
      other.lastLocationAt == lastLocationAt;

  @override
  int get hashCode => Object.hash(sessionId, token, createdAt, expiresAt,
      updateInterval, shareUrl, lastLocationAt);

  @override
  String toString() {
    final shortId =
        sessionId.length <= 8 ? sessionId : '${sessionId.substring(0, 8)}…';
    return 'LiveLocationSession($shortId, '
        'expires ${expiresAt.toIso8601String()}, never coordinates)';
  }
}
