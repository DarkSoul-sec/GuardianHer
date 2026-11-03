import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/result/result.dart';
import '../domain/location_failures.dart';
import '../domain/location_point.dart';


/// Diagnostic log prefix so `adb logcat` can filter location flow events.
///
/// PRIVACY: log lines carry only provider names, permission states, status
/// codes and durations — never coordinates, contact data or URLs. Output is
/// debug-only and never emitted in release builds.
const String locationDiagnosticsTag = 'LocationService';

void _log(String message) {
  if (kDebugMode) debugPrint('[$locationDiagnosticsTag] $message');
}

/// Permission states as reported by the native `guardianher/location_engine`.
enum EnginePermission { granted, denied, permanentlyDenied }

/// One raw fix handed over the platform channel.
@immutable
class EngineFix {
  const EngineFix({
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

  /// Wall-clock UTC time of the fix (display only).
  final int epochMs;

  /// Monotonic boot-scoped age of the fix in milliseconds. Correct across
  /// wall-clock changes AND reboots; all freshness decisions use this.
  final int ageMs;

  LocationPoint toLocationPoint({bool isStale = false}) {
    return LocationPoint(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true),
      isStale: isStale,
    );
  }
}

/// Thrown when the platform returns a response that cannot be trusted.
class EngineMalformedResponseException implements Exception {
  const EngineMalformedResponseException(this.detail);
  final String detail;
  @override
  String toString() => 'EngineMalformedResponseException($detail)';
}

/// Thin transport over the `guardianher/location_engine` channel.
///
/// Isolated behind an interface so the capture strategy below can be unit
/// tested without a platform channel.
abstract interface class LocationEngineClient {
  Future<bool> isServiceEnabled();
  Future<EnginePermission> checkPermission();
  Future<EnginePermission> requestPermission();
  Future<bool> openLocationSettings();
  Future<bool> enableSilently();
  Future<List<EngineFix>> getLastKnownLocations();

  /// One live fix from `gps` or `network`. Throws [PlatformException] with
  /// codes `servicesDisabled`, `timeout`, `providerFailed` or
  /// `permissionDenied` on failure.
  Future<EngineFix> requestSingleUpdate({
    required String provider,
    required Duration timeout,
  });
}

class MethodChannelLocationEngineClient implements LocationEngineClient {
  const MethodChannelLocationEngineClient();

  static const MethodChannel _channel =
      MethodChannel('guardianher/location_engine');

  @override
  Future<bool> isServiceEnabled() async =>
      await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;

  @override
  Future<EnginePermission> checkPermission() async =>
      _mapPermissionState(
          await _channel.invokeMethod<String>('checkPermission'));

  @override
  Future<EnginePermission> requestPermission() async =>
      _mapPermissionState(
          await _channel.invokeMethod<String>('requestPermission'));

  @override
  Future<bool> openLocationSettings() async =>
      await _channel.invokeMethod<bool>('openLocationSettings') ?? false;

  @override
  Future<bool> enableSilently() async =>
      await _channel.invokeMethod<bool>('enableSilently') ?? false;

  @override
  Future<List<EngineFix>> getLastKnownLocations() async {
    final raw = await _channel.invokeListMethod<dynamic>(
        'getLastKnownLocations');
    if (raw == null) return const [];
    return raw.map(_decodeFix).toList(growable: false);
  }

  @override
  Future<EngineFix> requestSingleUpdate({
    required String provider,
    required Duration timeout,
  }) async {
    final raw = await _channel.invokeMethod<dynamic>('requestSingleUpdate', {
      'provider': provider,
      'timeoutMs': timeout.inMilliseconds,
    });
    return _decodeFix(raw);
  }

  EnginePermission _mapPermissionState(String? state) {
    switch (state) {
      case 'granted':
        return EnginePermission.granted;
      case 'permanentlyDenied':
        return EnginePermission.permanentlyDenied;
      case 'denied':
        return EnginePermission.denied;
      default:
        throw const EngineMalformedResponseException('bad permission state');
    }
  }

  /// Defensively decodes a fix map; anything off-spec throws instead of
  /// producing coordinates the app would trust.
  EngineFix _decodeFix(dynamic raw) {
    if (raw is! Map) {
      throw const EngineMalformedResponseException('fix is not a map');
    }
    final provider = raw['provider'];
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    final accuracy = raw['accuracyMeters'];
    final epochMs = raw['epochMs'];
    final ageMs = raw['ageMs'];
    if (provider is! String ||
        latitude is! num ||
        longitude is! num ||
        accuracy is! num ||
        epochMs is! int ||
        ageMs is! int) {
      throw const EngineMalformedResponseException('fix field types');
    }
    return EngineFix(
      provider: provider,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      accuracyMeters: accuracy.toDouble(),
      epochMs: epochMs,
      ageMs: ageMs,
    );
  }
}

/// One-shot current location backed ONLY by Android's [LocationManager]
/// (`android.location`) — no Google Play Services anywhere.
///
/// F-Droid-first Phase 3H-1 replacement for the Geolocator plugin, whose
/// Android implementation bundles the proprietary play-services-location
/// library. V1 stays foreground-only: no streams, no background location,
/// no foreground service owned by this class.
///
/// Capture strategy (tunable via constructor):
///
/// * **Tier 0** — last-known fixes from GPS / NETWORK / PASSIVE. Fresh enough
///   ([lastKnownFreshWindow]) wins immediately. Older fixes are retained only
///   as explicitly stale fallback data and are NEVER returned as fresh.
/// * **Tier 1** — live GPS fix within [gpsTimeout].
/// * **Tier 2** — live network fix within [networkTimeout].
/// * If every live tier fails but a stale fallback exists, it is returned
///   with `isStale: true`; the UI labels it "last known". Otherwise a
///   truthful failure is reported.
///
/// Failure never crashes, never cancels SOS and never blocks emergency
/// calling — callers receive an [Err] result, nothing more.
class LocationManagerLocationService implements LocationService {
  LocationManagerLocationService({
    LocationEngineClient? engine,
    this.gpsTimeout = const Duration(seconds: 20),
    this.networkTimeout = const Duration(seconds: 15),
    this.lastKnownFreshWindow = const Duration(minutes: 15),
    this.staleFallbackMaxAge = const Duration(hours: 2),
  }) : _engine = engine ?? const MethodChannelLocationEngineClient();

  final LocationEngineClient _engine;

  /// Budget for the live GPS attempt.
  final Duration gpsTimeout;

  /// Budget for the live network attempt.
  final Duration networkTimeout;

  /// How recent a cached fix must be to be served instantly.
  final Duration lastKnownFreshWindow;

  /// Oldest cached fix still acceptable as a labeled fallback.
  final Duration staleFallbackMaxAge;

  @override
  Future<bool> isLocationServiceEnabled() async {
    try {
      final enabled = await _engine.isServiceEnabled();
      _log('isServiceEnabled -> $enabled');
      return enabled;
    } on Exception catch (error) {
      _log('isServiceEnabled threw (${error.runtimeType}); assuming on');
      // Mirror previous behavior: assume services are ON on a probe hiccup so
      // users are never sent to Settings because of a transient error; the
      // subsequent fix request reports truthfully anyway.
      return true;
    }
  }

  @override
  Future<PermissionStatus> checkPermission() async {
    try {
      final status = await _engine.checkPermission();
      _log('checkPermission -> $status');
      return _toDomain(status);
    } on EngineMalformedResponseException catch (error) {
      _log('checkPermission malformed: ${error.detail}');
      return PermissionStatus.denied;
    } on Exception catch (error) {
      _log('checkPermission threw (${error.runtimeType})');
      return PermissionStatus.denied;
    }
  }

  @override
  Future<PermissionStatus> requestPermission() async {
    try {
      final status = await _engine.requestPermission();
      _log('requestPermission -> $status');
      return _toDomain(status);
    } on EngineMalformedResponseException catch (error) {
      _log('requestPermission malformed: ${error.detail}');
      return PermissionStatus.denied;
    } on Exception catch (error) {
      _log('requestPermission threw (${error.runtimeType})');
      return PermissionStatus.denied;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      final opened = await _engine.openLocationSettings();
      _log('openLocationSettings -> $opened');
      return opened;
    } on Exception catch (error) {
      _log('openLocationSettings threw (${error.runtimeType})');
      return false;
    }
  }

  @override
  Future<bool> enableLocationServices() async {
    try {
      final enabled = await _engine.enableSilently();
      _log('enableSilently -> $enabled');
      return enabled;
    } on Exception catch (error) {
      _log('enableSilently threw (${error.runtimeType})');
      return false;
    }
  }

  @override
  Future<Result<LocationPoint>> getCurrentLocation() async {
    final captureWatch = Stopwatch()..start();
    _log('capture begin (freshWindow=${lastKnownFreshWindow.inMinutes}m, '
        'gps=${gpsTimeout.inMilliseconds}ms, '
        'network=${networkTimeout.inMilliseconds}ms)');
    try {
      final staleCandidate = await _tryLastKnown();
      if (staleCandidate != null && !staleCandidate.isStale) {
        captureWatch.stop();
        _log('capture end status=ok(fresh) source=last-known '
            'elapsed=${captureWatch.elapsedMilliseconds}ms');
        return Ok(staleCandidate);
      }

      var servicesDisabled = false;
      try {
        final gps = await _liveAttempt(
          provider: 'gps',
          timeout: gpsTimeout,
          tier: 1,
        );
        if (gps != null) {
          captureWatch.stop();
          _log('capture end status=ok(fresh) source=gps '
              'elapsed=${captureWatch.elapsedMilliseconds}ms');
          return Ok(gps);
        }
      } on LocationServicesDisabledFailure {
        _log('tier 1: services disabled');
        servicesDisabled = true;
      }

      try {
        final network = await _liveAttempt(
          provider: 'network',
          timeout: networkTimeout,
          tier: 2,
        );
        if (network != null) {
          captureWatch.stop();
          _log('capture end status=ok(fresh) source=network '
              'elapsed=${captureWatch.elapsedMilliseconds}ms');
          return Ok(network);
        }
      } on LocationServicesDisabledFailure {
        _log('tier 2: services disabled');
        servicesDisabled = true;
      }

      // A deterministic services-off report beats any cached data: the user
      // must flip the switch before anything can be trusted again.
      if (servicesDisabled) {
        captureWatch.stop();
        _log('capture end status=err(servicesDisabled) '
            'elapsed=${captureWatch.elapsedMilliseconds}ms');
        return const Err(LocationServicesDisabledFailure());
      }

      if (staleCandidate != null) {
        captureWatch.stop();
        _log('capture end status=ok(stale) elapsed='
            '${captureWatch.elapsedMilliseconds}ms');
        return Ok(staleCandidate);
      }
      captureWatch.stop();
      _log('capture end status=err(timeout) '
          'elapsed=${captureWatch.elapsedMilliseconds}ms');
      return const Err(LocationTimeoutFailure());
    } on Exception catch (error) {
      _log('getCurrentLocation threw (${error.runtimeType})');
      return const Err(LocationUnavailableFailure());
    }
  }

  /// Returns the freshest valid cached fix: non-stale while inside
  /// [lastKnownFreshWindow], otherwise marked stale if within
  /// [staleFallbackMaxAge]; null beyond that or when nothing exists.
  Future<LocationPoint?> _tryLastKnown() async {
    List<EngineFix> fixes;
    try {
      fixes = await _engine.getLastKnownLocations();
    } on Exception catch (error) {
      _log('last-known probe threw (${error.runtimeType})');
      return null;
    }
    if (fixes.isEmpty) {
      _log('last-known -> none cached');
      return null;
    }
    final freshest = fixes.reduce((a, b) => a.ageMs <= b.ageMs ? a : b);
    final point = freshest.toLocationPoint(isStale: true);
    if (!point.isValid) {
      _log('last-known discarded (invalid coordinates)');
      return null;
    }
    _log('last-known ${freshest.provider} age=${freshest.ageMs}ms '
        'accuracy=${point.accuracyMeters}');
    if (Duration(milliseconds: freshest.ageMs) <= lastKnownFreshWindow) {
      _log('last-known fresh fast path');
      return LocationPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        accuracyMeters: point.accuracyMeters,
        capturedAt: point.capturedAt,
      );
    }
    if (Duration(milliseconds: freshest.ageMs) <= staleFallbackMaxAge) {
      _log('last-known retained only as stale fallback');
      return point;
    }
    _log('last-known too old for any use');
    return null;
  }

  /// One live tier. Never throws: failures collapse to null so the next tier
  /// (or the truthful final failure) takes over.
  Future<LocationPoint?> _liveAttempt({
    required String provider,
    required Duration timeout,
    required int tier,
  }) async {
    try {
      final fix = await _engine.requestSingleUpdate(
        provider: provider,
        timeout: timeout,
      );
      final point = fix.toLocationPoint();
      if (!point.isValid) {
        _log('tier $tier ($provider) produced invalid coordinates');
        return null;
      }
      _log('tier $tier ($provider) fixed accuracy=${point.accuracyMeters}m');
      return point;
    } on PlatformException catch (error) {
      switch (error.code) {
        case 'servicesDisabled':
          _log('tier $tier ($provider): services disabled');
          throw LocationServicesDisabledFailure();
        case 'permissionDenied':
          _log('tier $tier ($provider): permission refused');
          return null;
        default:
          _log('tier $tier ($provider): ${error.code}');
          return null;
      }
    } on EngineMalformedResponseException catch (error) {
      _log('tier $tier ($provider) malformed response: ${error.detail}');
      return null;
    } on Exception catch (error) {
      _log('tier $tier ($provider) failed (${error.runtimeType})');
      return null;
    }
  }

  PermissionStatus _toDomain(EnginePermission status) {
    switch (status) {
      case EnginePermission.granted:
        return PermissionStatus.granted;
      case EnginePermission.permanentlyDenied:
        return PermissionStatus.permanentlyDenied;
      case EnginePermission.denied:
        return PermissionStatus.denied;
    }
  }
}
