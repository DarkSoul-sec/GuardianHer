import 'dart:async';

import 'package:flutter/services.dart';

/// Starts/stops the location foreground service that keeps the app in the
/// location foreground while a live-location session is active (Phase 3J §6).
///
/// Same pattern as `SosLocationService`: the service holds NO fix logic; it
/// exists so continuous capture survives screen-off/lock without
/// ACCESS_BACKGROUND_LOCATION, which GuardianHer does not request.
abstract interface class LiveLocationForegroundService {
  Future<void> start();

  Future<void> stop();
}

class LiveLocationForegroundServiceChannel
    implements LiveLocationForegroundService {
  const LiveLocationForegroundServiceChannel();

  static const MethodChannel _channel = MethodChannel('guardianher/live_location');

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// One raw fix from the native continuous engine. Mirrors `EngineFix` (same
/// wire map) but lives at the platform boundary so live_location never depends
/// on another feature's data layer.
class LiveFix {
  const LiveFix({
    required this.provider,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.epochMs,
    required this.ageMs,
  });

  final String provider;
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// Wall-clock UTC time of the fix.
  final int epochMs;

  /// Monotonic boot-scoped age of the fix in milliseconds.
  final int ageMs;
}

/// Continuous location fixes for an ACTIVE live session (§5).
///
/// Backed by `LocationManager.requestLocationUpdates` on GPS+NETWORK over the
/// `guardianher/location_updates` EventChannel — NOT a Dart loop of one-shot
/// requests. The stream is single-subscription: exactly one session consumes
/// it at a time, and [stopUpdates] must always be called on teardown so no
/// native listener outlives the session.
abstract interface class LiveLocationUpdates {
  /// Registers native listeners and begins emitting fixes. Throws
  /// [PlatformException] with code `permissionDenied` or `servicesDisabled`
  /// when tracking cannot start.
  Future<Stream<LiveFix>> startUpdates({required Duration interval});

  /// Removes every native listener. Idempotent.
  Future<void> stopUpdates();
}

class LiveLocationUpdatesChannel implements LiveLocationUpdates {
  LiveLocationUpdatesChannel();

  static const MethodChannel _engine =
      MethodChannel('guardianher/location_engine');
  static const EventChannel _events = EventChannel('guardianher/location_updates');

  Stream<LiveFix>? _stream;

  @override
  Future<Stream<LiveFix>> startUpdates({required Duration interval}) async {
    await _engine.invokeMethod<void>('startLiveUpdates', {
      'intervalMs': interval.inMilliseconds.clamp(1000, 300000),
    });
    // Single-broadcast wrapper: late subscribers after a session restart get
    // the fresh native registration created by the next startUpdates call.
    _stream ??= _events
        .receiveBroadcastStream()
        .map((dynamic event) => _decode(event));
    return _stream!;
  }

  @override
  Future<void> stopUpdates() async {
    await _engine.invokeMethod<void>('stopLiveUpdates');
  }

  static LiveFix _decode(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('live fix payload is not a map');
    }
    return LiveFix(
      provider: raw['provider'] as String? ?? 'unknown',
      latitude: (raw['latitude'] as num).toDouble(),
      longitude: (raw['longitude'] as num).toDouble(),
      accuracyMeters: (raw['accuracyMeters'] as num).toDouble(),
      epochMs: (raw['epochMs'] as num).toInt(),
      ageMs: (raw['ageMs'] as num).toInt(),
    );
  }
}
