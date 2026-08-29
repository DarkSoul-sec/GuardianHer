import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/domain/location_point.dart';
import 'package:guardianher/features/sos/application/sos_location_session_store.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

LocationState _stateWith(LocationStatus status, {bool stale = false}) {
  return LocationState(
    status: status,
    point: status == LocationStatus.captured
        ? LocationPoint(
            latitude: 1,
            longitude: 2,
            accuracyMeters: 5,
            capturedAt: DateTime.utc(2026, 1, 1, 12),
            isStale: stale,
          )
        : null,
  );
}

void main() {
  group('SosLocationSessionRecord codec', () {
    test('round-trips a captured snapshot', () {
      const record = SosLocationSessionRecord(
        sessionId: 'abc',
        state: 'captured',
        capturedAtEpochMs: 1700000000000,
        accuracyMeters: 12.5,
      );
      final decoded = SosLocationSessionRecord.tryDecode(record.encode());
      expect(decoded, isNotNull);
      expect(decoded!.sessionId, 'abc');
      expect(decoded.state, 'captured');
      expect(decoded.capturedAtEpochMs, 1700000000000);
      expect(decoded.accuracyMeters, 12.5);
      expect(decoded.failureCategory, isNull);
    });

    test('round-trips a failed snapshot with its category', () {
      const record = SosLocationSessionRecord(
        sessionId: 'abc',
        state: 'servicesDisabled',
        failureCategory: 'servicesDisabled',
      );
      final decoded = SosLocationSessionRecord.tryDecode(record.encode())!;
      expect(decoded.state, 'servicesDisabled');
      expect(decoded.failureCategory, 'servicesDisabled');
      expect(decoded.accuracyMeters, isNull);
    });

    test('rejects corrupt or off-spec payloads instead of trusting them', () {
      expect(SosLocationSessionRecord.tryDecode('not json'), isNull);
      expect(SosLocationSessionRecord.tryDecode('[1,2,3]'), isNull);
      expect(
        SosLocationSessionRecord.tryDecode(jsonEncode({'state': 'captured'})),
        isNull,
      );
    });
  });

  group('locationSessionStateOf', () {
    test('maps every truthful SOS location state', () {
      SosLocationSessionState mapOf(
        LocationStatus status, {
        bool stale = false,
      }) {
        return locationSessionStateOf(_stateWith(status, stale: stale));
      }

      expect(mapOf(LocationStatus.loading),
          SosLocationSessionState.loading);
      expect(mapOf(LocationStatus.captured),
          SosLocationSessionState.captured);
      expect(mapOf(LocationStatus.captured, stale: true),
          SosLocationSessionState.stale);
      expect(mapOf(LocationStatus.servicesDisabled),
          SosLocationSessionState.servicesDisabled);
      expect(mapOf(LocationStatus.denied),
          SosLocationSessionState.permissionDenied);
      expect(mapOf(LocationStatus.timeout), SosLocationSessionState.timeout);
      expect(mapOf(LocationStatus.unavailable),
          SosLocationSessionState.unavailable);
    });
  });

  group('SosActionController snapshot persistence', () {
    test('a capture while ACTIVE writes the coordinate-free snapshot',
        () async {
      final prefs = FakePreferencesService();
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          preferencesServiceProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await _settle();
      timer.fireComplete();
      await _settle();

      final raw = await prefs.getString(SosLocationSessionStore.storageKey);
      expect(raw, isNotNull);
      expect(raw, contains('"state":"captured"'));
      expect(raw, contains('"sessionId":"$testSosEventId"'));
      expect(raw, contains('"accuracyMeters":15'));
      // PRIVACY: no coordinates anywhere in the record.
      expect(raw, isNot(contains('latitude')));
      expect(raw, isNot(contains('longitude')));
      expect(raw, isNot(contains('12.345678')));
      expect(raw, isNot(contains('98.765432')));

      container.read(sosControllerProvider.notifier).cancelSos();
      await _settle();
      timer.fireComplete();
      await _settle();
      // Session ended → record dropped.
      expect(
        await prefs.getString(SosLocationSessionStore.storageKey),
        isNull,
      );
    });

    test('a timeout while ACTIVE persists its failure category', () async {
      final prefs = FakePreferencesService();
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          preferencesServiceProvider.overrideWithValue(prefs),
          locationServiceProvider.overrideWithValue(
            FakeLocationService(failure: const LocationTimeoutFailure()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await _settle();
      timer.fireComplete();
      await _settle();

      final raw = await prefs.getString(SosLocationSessionStore.storageKey);
      expect(raw, contains('"state":"timeout"'));
      expect(raw, contains('"failureCategory":"timeout"'));

      container.read(sosControllerProvider.notifier).cancelSos();
      await _settle();
      timer.fireComplete();
      await _settle();
    });

    test('no snapshot exists without an active session', () async {
      final prefs = FakePreferencesService();
      final container = createContainer(
        overrides: [
          preferencesServiceProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      await container.read(locationControllerProvider.notifier).captureLocation();

      expect(
        await prefs.getString(SosLocationSessionStore.storageKey),
        isNull,
      );
    });
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
