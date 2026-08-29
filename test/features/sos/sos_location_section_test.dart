import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/location_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/domain/location_point.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

/// [LocationService] fake whose capture hangs until released — models an
/// in-flight fix so the loading state can be observed deterministically.
class _HangingLocationService implements LocationService {
  final completer = Completer<Result<LocationPoint>>();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<PermissionStatus> checkPermission() async =>
      PermissionStatus.granted;

  @override
  Future<PermissionStatus> requestPermission() async =>
      PermissionStatus.granted;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<bool> enableLocationServices() async => false;

  @override
  Future<Result<LocationPoint>> getCurrentLocation() => completer.future;
}

void main() {
  Future<(ProviderContainer, FakeSosTimer)> pumpActiveSos(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    final timer = FakeSosTimer();
    final container = createContainer(
      overrides: [
        sosTimerProvider.overrideWithValue(timer),
        sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
        sosEventIdGeneratorProvider
            .overrideWithValue(() => SosEventId(testSosEventId)),
        vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
        callServiceProvider.overrideWithValue(FakeCallService()),
        smsServiceProvider.overrideWithValue(FakeSmsService()),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SosScreen()),
      ),
    );
    // Keep the side-effect coordinator alive like the real screen does.
    container.read(sosActionsControllerProvider);
    await tester.tap(find.widgetWithText(FilledButton, 'SOS'));
    await tester.pump();
    return (container, timer);
  }

  testWidgets('LOADING shows the in-progress wording and keep-open hint',
      (tester) async {
    final hanging = _HangingLocationService();
    final (container, timer) = await pumpActiveSos(
      tester,
      overrides: [locationServiceProvider.overrideWithValue(hanging)],
    );

    // The activation capture is still in flight.
    expect(container.read(locationControllerProvider).status,
        LocationStatus.loading);
    expect(find.text('Getting your location…'), findsOneWidget);
    expect(
      find.text('Please keep GuardianHer open if possible.'),
      findsOneWidget,
    );
    expect(find.text('SOS ACTIVE'), findsOneWidget);

    // Release so no pending work outlives the test.
    hanging.completer.complete(const Err(LocationUnavailableFailure()));
    await tester.pump();
    await endSession(tester, container, timer);
  });

  testWidgets('CAPTURED shows the honest accuracy line', (tester) async {
    await pumpActiveSos(tester);
    await tester.pump();

    expect(find.text('Location captured'), findsOneWidget);
    expect(find.text('Accuracy: ±15 m'), findsOneWidget);
    expect(find.textContaining('maps.google.com'), findsOneWidget);
  });

  testWidgets('STALE is labeled last known with its capture age',
      (tester) async {
    final stalePoint = LocationPoint(
      latitude: 12.345678,
      longitude: 98.765432,
      accuracyMeters: 40,
      capturedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 7)),
      isStale: true,
    );
    final (_, _) = await pumpActiveSos(
      tester,
      overrides: [
        locationServiceProvider
            .overrideWithValue(FakeLocationService(point: stalePoint)),
      ],
    );
    await tester.pump();

    expect(find.text('Last known location'), findsOneWidget);
    expect(find.text('Updated 7 minutes ago'), findsOneWidget);
    // Never presented as a current capture on this screen.
    expect(find.text('Location captured'), findsNothing);
  });

  testWidgets('DISABLED names the switch and its consequence',
      (tester) async {
    final (container, timer) = await pumpActiveSos(
      tester,
      overrides: [
        locationServiceProvider
            .overrideWithValue(FakeLocationService(enabled: false)),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] = PermissionStatus.granted,
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Location is turned off'), findsOneWidget);
    expect(
      find.text('Your SOS is active, but your location could not be obtained.'),
      findsOneWidget,
    );
    expect(find.text('Turn on location'), findsOneWidget);
    expect(find.text('End SOS'), findsOneWidget);

    // End the session so the pending location retry is cancelled.
    await endSession(tester, container, timer);
  });

  testWidgets('PERMISSION_DENIED offers the settings recovery',
      (tester) async {
    final (_, _) = await pumpActiveSos(
      tester,
      overrides: [
        locationServiceProvider.overrideWithValue(
          FakeLocationService(permission: PermissionStatus.permanentlyDenied),
        ),
        permissionServiceProvider.overrideWithValue(
          FakePermissionService()
            ..statuses[AppPermission.location] =
                PermissionStatus.permanentlyDenied,
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Location permission unavailable'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('TIMEOUT is distinct and retryable without ending SOS',
      (tester) async {
    final location = FakeLocationService(failure: const LocationTimeoutFailure());
    final (container, timer) = await pumpActiveSos(
      tester,
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        sosLocationRetryDelayProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't get your current location"), findsOneWidget);
    expect(find.text('Location unavailable'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('SOS ACTIVE'), findsOneWidget);

    // Manual retry re-runs the capture while the session stays active.
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(location.captureCount, 2);
    expect(container.read(sosControllerProvider), isA<SosActive>());

    await endSession(tester, container, timer);
  });

  testWidgets('UNAVAILABLE stays truthful and never blocks the session',
      (tester) async {
    final (container, timer) = await pumpActiveSos(
      tester,
      overrides: [
        locationServiceProvider.overrideWithValue(
          FakeLocationService(failure: const LocationUnavailableFailure()),
        ),
        sosLocationRetryDelayProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Location unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('End SOS'), findsOneWidget);
    expect(container.read(sosControllerProvider), isA<SosActive>());

    // End the session so the pending location retry is cancelled.
    await endSession(tester, container, timer);
  });
}

/// Cancels the active session and flushes the async cancel chain so the
/// location-retry timer is disposed before the test's timer invariant fires.
Future<void> endSession(
  WidgetTester tester,
  ProviderContainer container,
  FakeSosTimer timer,
) async {
  container.read(sosControllerProvider.notifier).cancelSos();
  await tester.pump();
  timer.fireComplete();
  await tester.pump();
}
