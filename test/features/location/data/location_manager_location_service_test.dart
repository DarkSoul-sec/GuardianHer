import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/features/location/data/location_manager_location_service.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/domain/location_point.dart';

/// Scripted [LocationEngineClient]: deterministic responses without any
/// platform channel involvement.
class _FakeEngineClient implements LocationEngineClient {
  _FakeEngineClient({
    this.serviceEnabled = true,
    this.probeThrows = false,
    this.permission = EnginePermission.denied,
  });

  bool serviceEnabled;

  /// When true the service-state probe throws instead of answering.
  bool probeThrows;

  EnginePermission permission;

  /// Cached fixes returned by [getLastKnownLocations].
  List<EngineFix> lastKnown = const [];

  /// Per-provider live-update outcome: an [EngineFix] resolves successfully,
  /// a [String] is thrown as a [PlatformException] with that code.
  final Map<String, Object> updateOutcomes = {};

  int gpsCalls = 0;
  int networkCalls = 0;
  int enableSilentlyCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<bool> isServiceEnabled() async {
    if (probeThrows) {
      throw PlatformException(code: 'unavailable');
    }
    return serviceEnabled;
  }

  @override
  Future<EnginePermission> checkPermission() async => permission;

  @override
  Future<EnginePermission> requestPermission() async => permission;

  @override
  Future<bool> openLocationSettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<bool> enableSilently() async {
    enableSilentlyCalls++;
    return false;
  }

  @override
  Future<List<EngineFix>> getLastKnownLocations() async => lastKnown;

  @override
  Future<EngineFix> requestSingleUpdate({
    required String provider,
    required Duration timeout,
  }) async {
    if (provider == 'gps') {
      gpsCalls++;
    } else if (provider == 'network') {
      networkCalls++;
    }
    final outcome = updateOutcomes[provider];
    if (outcome == null || outcome is String) {
      throw PlatformException(
        code: outcome as String? ?? 'timeout',
        message: provider,
      );
    }
    return outcome as EngineFix;
  }
}

EngineFix _fix({
  String provider = 'gps',
  double lat = 12.9716,
  double lng = 77.5946,
  double accuracy = 20,
  int ageMs = 0,
}) {
  return EngineFix(
    provider: provider,
    latitude: lat,
    longitude: lng,
    accuracyMeters: accuracy,
    epochMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch - ageMs,
    ageMs: ageMs,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationManagerLocationService', () {
    group('service state', () {
      test('reports the native service state', () async {
        final client = _FakeEngineClient(serviceEnabled: true);
        final service = LocationManagerLocationService(engine: client);
        expect(await service.isLocationServiceEnabled(), isTrue);
      });

      test('a failing probe assumes services ON (never traps user in Settings)',
          () async {
        final client = _FakeEngineClient(probeThrows: true);
        final service = LocationManagerLocationService(engine: client);
        expect(await service.isLocationServiceEnabled(), isTrue);
      });
    });

    group('permission mapping', () {
      test('granted maps to granted', () async {
        final client = _FakeEngineClient(permission: EnginePermission.granted);
        final service = LocationManagerLocationService(engine: client);
        expect(await service.checkPermission(), PermissionStatus.granted);
      });

      test('denied maps to denied', () async {
        final client = _FakeEngineClient(permission: EnginePermission.denied);
        final service = LocationManagerLocationService(engine: client);
        expect(await service.checkPermission(), PermissionStatus.denied);
      });

      test('permanentlyDenied maps to permanentlyDenied', () async {
        final client =
            _FakeEngineClient(permission: EnginePermission.permanentlyDenied);
        final service = LocationManagerLocationService(engine: client);
        expect(
          await service.requestPermission(),
          PermissionStatus.permanentlyDenied,
        );
      });
    });

    group('getCurrentLocation tiers', () {
      test('services disabled surfaces as a truthful services-off failure',
          () async {
        final client = _FakeEngineClient()
          ..updateOutcomes['gps'] = 'servicesDisabled'
          ..updateOutcomes['network'] = 'servicesDisabled';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        expect(result.isErr, isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (failure) =>
              expect(failure, isA<LocationServicesDisabledFailure>()),
        );
      });

      test('a FRESH last-known fix wins instantly without live requests',
          () async {
        final client = _FakeEngineClient()
          ..lastKnown = [_fix(provider: 'passive', ageMs: 30_000)];
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        expect(client.gpsCalls, 0);
        expect(client.networkCalls, 0);
        final point = result.getOrNull()!;
        expect(point, isA<LocationPoint>());
        expect(point.isStale, isFalse);
        expect(point.capturedAt.isUtc, isTrue);
      });

      test('the freshest cached fix wins across GPS/NETWORK/PASSIVE',
          () async {
        final client = _FakeEngineClient()
          ..lastKnown = [
            _fix(provider: 'gps', ageMs: 120_000),
            _fix(provider: 'network', ageMs: 5_000),
            _fix(provider: 'passive', ageMs: 60_000),
          ];
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        // The network fix is freshest and inside the freshness window.
        expect(client.gpsCalls, 0);
        expect(result.getOrNull()!.accuracyMeters, 20);
        expect(result.getOrNull()!.isStale, isFalse);
      });

      test('tier 1 delivers a live GPS fix and skips the network tier',
          () async {
        final client = _FakeEngineClient()
          ..updateOutcomes['gps'] = _fix();
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        expect(client.gpsCalls, 1);
        expect(client.networkCalls, 0);
        expect(result.getOrNull()!.isStale, isFalse);
      });

      test('falls back to NETWORK when GPS times out', () async {
        final client = _FakeEngineClient()
          ..updateOutcomes['gps'] = 'timeout'
          ..updateOutcomes['network'] = _fix(provider: 'network');
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        expect(client.gpsCalls, 1);
        expect(client.networkCalls, 1);
        expect(result.getOrNull()!.isStale, isFalse);
      });

      test('both live tiers timing out with no cache yields a timeout failure',
          () async {
        final client = _FakeEngineClient()
          ..updateOutcomes['gps'] = 'timeout'
          ..updateOutcomes['network'] = 'timeout';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        result.fold(
          (_) => fail('expected failure'),
          (failure) => expect(failure, isA<LocationTimeoutFailure>()),
        );
      });
    });

    group('stale fallback honesty', () {
      test('an OLD-but-usable cache is served only as EXPLICITLY STALE data',
          () async {
        final client = _FakeEngineClient()
          ..lastKnown = [
            _fix(ageMs: 90 * 60 * 1000), // 90 minutes old.
          ]
          ..updateOutcomes['gps'] = 'timeout'
          ..updateOutcomes['network'] = 'timeout';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        expect(client.gpsCalls, 1, reason: 'live tiers must still be tried');
        expect(client.networkCalls, 1);
        final point = result.getOrNull()!;
        expect(point.isStale, isTrue,
            reason: 'stale data must never pose as a fresh fix');
      });

      test('a cache older than the fallback horizon is discarded entirely',
          () async {
        final client = _FakeEngineClient()
          ..lastKnown = [
            _fix(ageMs: 5 * 60 * 60 * 1000), // 5 hours old.
          ]
          ..updateOutcomes['gps'] = 'timeout'
          ..updateOutcomes['network'] = 'timeout';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        result.fold(
          (_) => fail('expected failure'),
          (failure) => expect(failure, isA<LocationTimeoutFailure>()),
        );
      });

      test('services-disabled beats any stale fallback', () async {
        final client = _FakeEngineClient()
          ..lastKnown = [_fix(ageMs: 90 * 60 * 1000)]
          ..updateOutcomes['gps'] = 'servicesDisabled';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        result.fold(
          (_) => fail('expected failure'),
          (failure) =>
              expect(failure, isA<LocationServicesDisabledFailure>()),
        );
      });
    });

    group('hostile input resilience', () {
      test('malformed cached fixes are ignored, not trusted', () async {
        final client = _FakeEngineClient()
          ..lastKnown = [
            EngineFix(
              provider: 'gps',
              latitude: 999, // Invalid latitude.
              longitude: 77.5946,
              accuracyMeters: 20,
              epochMs: 1,
              ageMs: 1000,
            ),
          ]
          ..updateOutcomes['gps'] = 'timeout'
          ..updateOutcomes['network'] = 'timeout';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        result.fold(
          (_) => fail('invalid coordinates must not be served'),
          (failure) => expect(failure, isA<LocationTimeoutFailure>()),
        );
      });

      test('malformed live fixes fall through instead of crashing', () async {
        final client = _FakeEngineClient()
          ..updateOutcomes['gps'] = _fix(lat: -500)
          ..updateOutcomes['network'] = 'providerFailed';
        final service = LocationManagerLocationService(engine: client);

        final result = await service.getCurrentLocation();

        expect(client.networkCalls, 1,
            reason: 'invalid GPS output must still try the next tier');
        expect(result.isErr, isTrue);
      });

      test('a transport-level exception degrades to unavailable, never throws',
          () async {
        final client = _FakeEngineClient(probeThrows: true)
          ..lastKnown = const []
          // Force getLastKnownLocations itself to blow up via a bad cast path:
          // emulate by throwing inside the fake through a PlatformException.
          ;
        final service = LocationManagerLocationService(
          engine: _ThrowingLastKnownClient(client),
          gpsTimeout: const Duration(milliseconds: 50),
          networkTimeout: const Duration(milliseconds: 50),
        );

        final result = await service.getCurrentLocation();

        expect(result.isErr, isTrue);
      });
    });

    test('settings/silent-enable delegate to the engine', () async {
      final client = _FakeEngineClient();
      final service = LocationManagerLocationService(engine: client);

      expect(await service.openLocationSettings(), isTrue);
      expect(await service.enableLocationServices(), isFalse);
      expect(client.openSettingsCalls, 1);
      expect(client.enableSilentlyCalls, 1);
    });
  });
}

/// Wraps a client whose [getLastKnownLocations] always throws, emulating a
/// malformed transport response end-to-end.
class _ThrowingLastKnownClient implements LocationEngineClient {
  _ThrowingLastKnownClient(this.inner);
  final _FakeEngineClient inner;

  @override
  Future<bool> isServiceEnabled() => inner.isServiceEnabled();

  @override
  Future<EnginePermission> checkPermission() => inner.checkPermission();

  @override
  Future<EnginePermission> requestPermission() => inner.requestPermission();

  @override
  Future<bool> openLocationSettings() => inner.openLocationSettings();

  @override
  Future<bool> enableSilently() => inner.enableSilently();

  @override
  Future<List<EngineFix>> getLastKnownLocations() async {
    throw PlatformException(code: 'unavailable', message: 'garbled payload');
  }

  @override
  Future<EngineFix> requestSingleUpdate({
    required String provider,
    required Duration timeout,
  }) =>
      inner.requestSingleUpdate(provider: provider, timeout: timeout);
}
