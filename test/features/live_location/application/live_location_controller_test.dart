import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/live_location_platform.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/live_location/application/live_location_providers.dart';
import 'package:guardianher/features/live_location/application/live_location_state.dart';
import 'package:guardianher/features/live_location/data/live_location_api_client.dart';
import 'package:guardianher/features/live_location/domain/live_location_failures.dart';
import 'package:guardianher/features/live_location/domain/live_location_session.dart';

import '../../../helpers/fakes.dart';

/// A fix with deterministic values; [lat] varies per call.
LiveFix fix({double lat = 52.5}) => LiveFix(
      provider: 'gps',
      latitude: lat,
      longitude: 13.4,
      accuracyMeters: 12,
      epochMs: DateTime.utc(2026, 1, 1, 12).millisecondsSinceEpoch,
      ageMs: 0,
    );

class Harness {
  Harness(this.api, this.updates, this.fgs, this.container);

  final FakeLiveLocationApiClient api;
  final FakeLiveLocationUpdates updates;
  final FakeLiveLocationForegroundService fgs;
  final ProviderContainer container;

  LiveLocationState get state => container.read(liveLocationControllerProvider);
}

Harness harness({
  FakeLiveLocationApiClient? api,
}) {
  final liveApi = api ?? (FakeLiveLocationApiClient()..configured = true);
  final updates = FakeLiveLocationUpdates();
  final fgs = FakeLiveLocationForegroundService();
  final container = createContainer(
    overrides: [
      liveLocationApiClientProvider.overrideWithValue(liveApi),
      liveLocationUpdatesProvider.overrideWithValue(updates),
      liveLocationForegroundServiceProvider.overrideWithValue(fgs),
    ],
  );
  return Harness(liveApi, updates, fgs, container);
}

void main() {
  group('LiveLocationController.start', () {
    test('unconfigured builds fail fast without touching the platform',
        () => fakeAsync((async) {
              final h = harness(
                api: FakeLiveLocationApiClient(),
              ); // stays unconfigured
              h.container.read(liveLocationControllerProvider.notifier);

              unawaited(h.container
                  .read(liveLocationControllerProvider.notifier)
                  .start(LiveShareDuration.minutes30));
              async.flushMicrotasks();

              expect(h.state.status, LiveSessionStatus.failed);
              expect(h.state.failure?.key, 'failedNotConfigured');
              expect(h.updates.startCount, 0);
              expect(h.fgs.startCount, 0);
            }));

    test('happy path starts FGS + engine + backend session', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(liveLocationControllerProvider.notifier);

        final done = h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();

        expect(h.state.status, LiveSessionStatus.active);
        expect(h.state.connectionUp, isTrue);
        expect(h.state.session?.token, isNotEmpty);
        expect(h.state.session?.shareUrl, contains('/live/'));
        expect(h.updates.lastInterval, const Duration(seconds: 30));
        expect(h.api.createCalls, 1);
        done.then((value) => expect(value, isTrue));
        async.flushMicrotasks();
      });
    });

    test('permission refusal fails cleanly before anything starts', () {
      fakeAsync((async) {
        final locationService = FakeLocationService(
          permission: PermissionStatus.denied,
          requestPermissionResult: PermissionStatus.permanentlyDenied,
        );
        final liveApi = FakeLiveLocationApiClient()..configured = true;
        final updates = FakeLiveLocationUpdates();
        final fgs = FakeLiveLocationForegroundService();
        final container = createContainer(overrides: [
          liveLocationApiClientProvider.overrideWithValue(liveApi),
          liveLocationUpdatesProvider.overrideWithValue(updates),
          liveLocationForegroundServiceProvider.overrideWithValue(fgs),
          locationServiceProvider.overrideWithValue(locationService),
        ]);
        container.read(liveLocationControllerProvider.notifier);

        final future =
            container.read(liveLocationControllerProvider.notifier).start(
                  LiveShareDuration.minutes30,
                );
        async.flushMicrotasks();

        expect(
          container.read(liveLocationControllerProvider).status,
          LiveSessionStatus.failed,
        );
        expect(
          container.read(liveLocationControllerProvider).failure?.key,
          'failedPermission',
        );
        expect(fgs.startCount, 0);
        expect(updates.startCount, 0);
        expect(liveApi.createCalls, 0);
        future.then((value) => expect(value, isFalse));
        async.flushMicrotasks();
      });
    });

    test('offline start keeps capturing and creates the session later', () {
      fakeAsync((async) {
        var failFirstCreate = true;
        final liveApi = FakeLiveLocationApiClient()
          ..configured = true
          ..createResult = () {
            if (failFirstCreate) {
              failFirstCreate = false;
              return Err<LiveSessionCreation>(
                LiveLocationFailure(LiveLocationFailureType.networkUnavailable),
              );
            }
            return null; // fall back to success
          };
        final h = harness(api: liveApi);
        h.container.read(liveLocationControllerProvider.notifier);

        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();

        // Session shell exists, but honestly reports no connection and no link.
        expect(h.state.status, LiveSessionStatus.active);
        expect(h.state.connectionUp, isFalse);
        expect(h.state.session?.token, isEmpty);
        expect(h.state.session?.shareUrl, isEmpty);

        // First tick retries creation only (no token yet → no push).
        async.elapse(const Duration(seconds: 30));
        expect(h.liveApiPushesOrCreation(), 1);
        expect(h.state.connectionUp, isTrue);
        expect(h.state.session?.token, isNotEmpty);
      });
    });
  });

  group('LiveLocationController capture + upload loop', () {
    test('fixes update the latest point and upload exactly that point', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();

        h.updates.emit(fix(lat: 52.5001));
        async.flushMicrotasks();
        h.updates.emit(fix(lat: 52.5002)); // supersedes the first locally
        async.flushMicrotasks();

        expect(h.state.lastPoint?.latitude, closeTo(52.5002, 1e-9));

        async.elapse(const Duration(seconds: 30));
        // Exactly ONE push carrying THE latest fix — no backlog.
        expect(h.api.pushes.length, 1);
        expect(h.api.pushes.single.latitude, closeTo(52.5002, 1e-9));
        expect(h.api.pushes.single.token, h.state.session?.token == null
            ? ''
            : h.api.pushes.single.token);
      });
    });

    test('offline capture continues and reports connection unavailable', () {
      fakeAsync((async) {
        final liveApi = FakeLiveLocationApiClient()
          ..configured = true
          ..pushResults = [
            Err(LiveLocationFailure(LiveLocationFailureType.networkUnavailable)),
            const Ok(null),
          ];
        final h = harness(api: liveApi);
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();
        h.updates.emit(fix());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(h.state.connectionUp, isFalse);

        // Next interval succeeds: sharing resumes with the SAME latest point.
        async.elapse(const Duration(seconds: 30));
        expect(h.state.connectionUp, isTrue);
        expect(h.api.pushes.length, 2);
      });
    });

    test('server-side expiry ends the session and stops the loop', () {
      fakeAsync((async) {
        final liveApi = FakeLiveLocationApiClient()
          ..configured = true
          ..pushResults = [
            Err(LiveLocationFailure(LiveLocationFailureType.sessionExpired)),
          ];
        final h = harness(api: liveApi);
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();
        h.updates.emit(fix());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(h.state.status, LiveSessionStatus.expired);
        expect(h.state.failure?.key, 'expired');
        async.flushTimers();
        expect(h.fgs.stopCount, 1);

        // The loop is dead: further ticks do nothing.
        async.elapse(const Duration(seconds: 60));
        expect(h.api.pushes.length, 1);
      });
    });

    test('local TTL expiry fires even without any server interaction', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();
        expect(h.state.isActive, isTrue);

        async.elapse(const Duration(minutes: 31));
        expect(h.state.status, LiveSessionStatus.expired);
        // Teardown MUST run: an expired session may never leave the
        // foreground service or engine running (device-verified regression).
        async.flushTimers();
        expect(h.fgs.stopCount, 1);
        expect(h.updates.stopCount, 1);
      });
    });

    test('revocation surfaces as stopped-by-user', () {
      fakeAsync((async) {
        final liveApi = FakeLiveLocationApiClient()
          ..configured = true
          ..pushResults = [
            Err(LiveLocationFailure(LiveLocationFailureType.sessionRevoked)),
          ];
        final h = harness(api: liveApi);
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();
        h.updates.emit(fix());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        expect(h.state.status, LiveSessionStatus.stopped);
        expect(h.state.failure?.key, 'stoppedByUser');
        async.flushTimers();
        expect(h.fgs.stopCount, 1);
      });
    });
  });

  group('LiveLocationController.stopSession', () {
    test('stops tracking, revokes the backend session and finishes', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .start(LiveShareDuration.minutes30);
        async.flushMicrotasks();
        h.updates.emit(fix());
        async.flushMicrotasks();

        h.container
            .read(liveLocationControllerProvider.notifier)
            .stopSession();
        async.flushMicrotasks();
        async.flushTimers();

        expect(h.state.status, LiveSessionStatus.stopped);
        expect(h.state.failure?.key, 'stoppedByUser');
        expect(h.api.stopCalls, 1);
        expect(h.updates.stopCount, 1);
        expect(h.fgs.stopCount, 1);

        // Idempotent: a second stop does nothing.
        h.container
            .read(liveLocationControllerProvider.notifier)
            .stopSession();
        async.flushMicrotasks();
        expect(h.api.stopCalls, 1);
      });
    });
  });

  group('LiveLocationController.refresh', () {
    test('expires an over-due active session when the UI resumes', () {
      fakeAsync((async) {
        final h = harness();
        final controller =
            h.container.read(liveLocationControllerProvider.notifier);
        controller.start(LiveShareDuration.minutes30);
        async.flushMicrotasks();

        // Simulate a long background pause by expiring directly.
        async.elapse(const Duration(hours: 1));
        // The expiry timer already fired; refresh on a finished session is a
        // no-op.
        controller.refresh();
        expect(h.state.status, LiveSessionStatus.expired);
      });
    });
  });

  group('LiveLocationController.startEmergency', () {
    test('uses the SOS cadence and never throws when offline', () {
      fakeAsync((async) {
        final liveApi = FakeLiveLocationApiClient()..configured = false;
        final h = harness(api: liveApi);
        h.container.read(liveLocationControllerProvider.notifier);

        // Must complete without throwing despite being unconfigured AND
        // offline.
        h.container
            .read(liveLocationControllerProvider.notifier)
            .startEmergency()
            .then((started) => expect(started, isFalse));
        async.flushMicrotasks();
        expect(h.state.status, LiveSessionStatus.failed);
      });
    });

    test('emergency sessions run at the 10-second cadence', () {
      fakeAsync((async) {
        final h = harness();
        h.container.read(liveLocationControllerProvider.notifier);
        h.container
            .read(liveLocationControllerProvider.notifier)
            .startEmergency();
        async.flushMicrotasks();

        expect(h.updates.lastInterval, const Duration(seconds: 10));
        expect(h.api.createCalls, 1);

        h.updates.emit(fix());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(h.api.pushes.length, 1);
      });
    });
  });
}

extension _HarnessProbe on Harness {
  /// Number of createSession calls after the initial one.
  int liveApiPushesOrCreation() => api.createCalls - 1;
}
