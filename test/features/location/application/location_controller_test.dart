import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/platform/location_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/domain/location_format.dart';
import 'package:guardianher/features/location/domain/location_point.dart';

import '../../../helpers/fakes.dart';
import '../../sos/sos_test_fakes.dart';

/// A [LocationService] whose fix future the test completes manually, so it can
/// model an in-flight capture that outlives a [reset].
class HangingLocationService implements LocationService {
  HangingLocationService({this.permission = PermissionStatus.granted});

  PermissionStatus permission;
  final List<Completer<Result<LocationPoint>>> completers = [];

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<PermissionStatus> checkPermission() async => permission;

  @override
  Future<PermissionStatus> requestPermission() async => permission;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<bool> enableLocationServices() async => false;

  @override
  Future<Result<LocationPoint>> getCurrentLocation() {
    final completer = Completer<Result<LocationPoint>>();
    completers.add(completer);
    return completer.future;
  }
}

void main() {
  group('LocationController.captureLocation', () {
    test('captures a fix when services and permission are already granted',
        () async {
      final service = FakeLocationService();
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      final state = container.read(locationControllerProvider);
      expect(state.status, LocationStatus.captured);
      expect(state.point, testLocationPoint);
      expect(service.permissionRequestCount, 0);
    });

    test('requests permission only when retryable, then captures', () async {
      final service = FakeLocationService(
        permission: PermissionStatus.denied,
        requestPermissionResult: PermissionStatus.granted,
      );
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      expect(service.permissionRequestCount, 1);
      expect(container.read(locationControllerProvider).status,
          LocationStatus.captured);
    });

    test('permanently denied permission opens settings and never fixes',
        () async {
      final service = FakeLocationService(
        permission: PermissionStatus.permanentlyDenied,
      );
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      final state = container.read(locationControllerProvider);
      expect(state.status, LocationStatus.denied);
      expect(state.openSettings, isTrue);
      expect(service.captureCount, 0);
    });

    test('a declined permission request reports a retryable denial', () async {
      final service = FakeLocationService(
        permission: PermissionStatus.denied,
        requestPermissionResult: PermissionStatus.denied,
      );
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      final state = container.read(locationControllerProvider);
      expect(state.status, LocationStatus.denied);
      expect(state.canRetry, isTrue);
      expect(state.openSettings, isFalse);
      expect(service.captureCount, 0);
    });

    test('disabled location services report settings recovery', () async {
      final service = FakeLocationService(enabled: false);
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      final state = container.read(locationControllerProvider);
      expect(state.status, LocationStatus.servicesDisabled);
      expect(state.openLocationSettings, isTrue);
      expect(state.openSettings, isFalse);
      expect(state.canRetry, isFalse);
      expect(service.captureCount, 0);
    });

    test('a fix timeout surfaces as a distinct timeout state with retry',
        () async {
      final service = FakeLocationService(
        failure: const LocationTimeoutFailure(),
      );
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      final state = container.read(locationControllerProvider);
      expect(state.status, LocationStatus.timeout);
      expect(state.canRetry, isTrue);
      expect(state.message, contains('could not be determined'));
    });

    test('a non-timeout failure surfaces as unavailable with retry', () async {
      final service = FakeLocationService(
        failure: const LocationUnavailableFailure(),
      );
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(locationControllerProvider.notifier).captureLocation();

      final state = container.read(locationControllerProvider);
      expect(state.status, LocationStatus.unavailable);
      expect(state.canRetry, isTrue);
    });

    test('a duplicate request while loading is ignored', () async {
      final service = FakeLocationService();
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      final first = controller.captureLocation();
      final second = controller.captureLocation();
      await first;
      await second;

      // The loading guard swallows the second request.
      expect(service.captureCount, 1);
    });
  });

  group('LocationController.openInMaps', () {
    test('fails without a captured point', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final result =
          await container.read(locationControllerProvider.notifier).openInMaps();

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure, isA<LocationUnavailableFailure>());
    });

    test('opens the captured point in the map service', () async {
      final map = FakeMapService();
      final container = createContainer(
        overrides: [
          mapServiceProvider.overrideWithValue(map),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      final result = await controller.openInMaps();

      expect(result, isA<Ok<void>>());
      expect(map.lastOpened, testLocationPoint);
    });
  });

  group('LocationController.shareLocation', () {
    test('fails without a captured point', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final result = await container
          .read(locationControllerProvider.notifier)
          .shareLocation();

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure, isA<LocationUnavailableFailure>());
    });

    test('opens the SMS composer with no recipient and the location message',
        () async {
      final sms = FakeSmsService();
      final container = createContainer(
        overrides: [
          smsServiceProvider.overrideWithValue(sms),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      final result = await controller.shareLocation();

      expect(result, isA<Ok<void>>());
      expect(sms.opened, hasLength(1));
      expect(sms.opened.single.phoneNumber, isEmpty);
      expect(
        sms.opened.single.body,
        'GuardianHer SOS alert\n'
        'Current location captured at '
        '${formatCapturedTime(testLocationPoint.capturedAt)}\n'
        'https://maps.google.com/?q=12.345678,98.765432',
      );
    });

    test('falls back to the share sheet when no SMS app is available',
        () async {
      final sms = FakeSmsService()
        ..result = const Err(NoSmsAppAvailableFailure());
      final share = FakeShareService();
      final container = createContainer(
        overrides: [
          smsServiceProvider.overrideWithValue(sms),
          shareServiceProvider.overrideWithValue(share),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      final result = await controller.shareLocation();

      expect(result, isA<Ok<void>>());
      expect(sms.opened, hasLength(1));
      expect(
        share.shared.single,
        'GuardianHer SOS alert\n'
        'Current location captured at '
        '${formatCapturedTime(testLocationPoint.capturedAt)}\n'
        'https://maps.google.com/?q=12.345678,98.765432',
      );
    });

    test('propagates non-availability SMS failures without sharing',
        () async {
      final sms = FakeSmsService()..result = const Err(PlatformActionFailure());
      final share = FakeShareService();
      final container = createContainer(
        overrides: [
          smsServiceProvider.overrideWithValue(sms),
          shareServiceProvider.overrideWithValue(share),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      final result = await controller.shareLocation();

      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure, isA<PlatformActionFailure>());
      expect(share.shared, isEmpty);
    });
  });

  group('LocationController.reset', () {
    test('returns to idle and drops the captured point', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      expect(container.read(locationControllerProvider).status,
          LocationStatus.captured);

      controller.reset();
      expect(container.read(locationControllerProvider).status,
          LocationStatus.idle);
      expect(container.read(locationControllerProvider).point, isNull);
    });

    test('clears a stuck loading state while a capture is in flight', () async {
      final service = HangingLocationService();
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      final capture = controller.captureLocation();
      expect(container.read(locationControllerProvider).status,
          LocationStatus.loading);

      // Let the capture reach the in-flight fix request.
      await Future<void>.delayed(Duration.zero);
      expect(service.completers, hasLength(1));

      // reset() takes effect even while loading — no permanent spinner.
      controller.reset();
      expect(container.read(locationControllerProvider).status,
          LocationStatus.idle);

      // The stale in-flight result must never resurrect the state.
      service.completers.single.complete(Ok(testLocationPoint));
      await capture;
      expect(container.read(locationControllerProvider).status,
          LocationStatus.idle);
      expect(container.read(locationControllerProvider).point, isNull);
    });

    test('a failed capture that finishes after reset is also discarded',
        () async {
      final service = HangingLocationService();
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      final capture = controller.captureLocation();
      await Future<void>.delayed(Duration.zero);
      controller.reset();
      service.completers.single.complete(const Err(LocationTimeoutFailure()));
      await capture;

      expect(container.read(locationControllerProvider).status,
          LocationStatus.idle);
    });

    test('capture works again after a reset superseded the first attempt',
        () async {
      final service = HangingLocationService();
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      final first = controller.captureLocation();
      await Future<void>.delayed(Duration.zero);
      controller.reset();
      service.completers.first.complete(Ok(testLocationPoint));
      await first;

      // A new capture after the reset starts a fresh request and resolves.
      final second = controller.captureLocation();
      await Future<void>.delayed(Duration.zero);
      expect(service.completers, hasLength(2));
      service.completers[1].complete(Ok(testLocationPoint));
      await second;

      expect(container.read(locationControllerProvider).status,
          LocationStatus.captured);
    });
  });

  group('LocationController.openLocationSettings', () {
    test('opens the device settings then auto-resumes the capture', () async {
      final service = FakeLocationService(enabled: false);
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      expect(container.read(locationControllerProvider).status,
          LocationStatus.servicesDisabled);
      expect(service.openLocationSettingsCount, 0);

      // The user enables GPS while in the device settings, then returns.
      service.enabled = true;
      await controller.openLocationSettings();

      expect(service.openLocationSettingsCount, 1);
      expect(container.read(locationControllerProvider).status,
          LocationStatus.captured);
    });

    test('does not resume when services stayed off', () async {
      final service = FakeLocationService(enabled: false);
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      await controller.openLocationSettings();

      expect(service.openLocationSettingsCount, 1);
      expect(container.read(locationControllerProvider).status,
          LocationStatus.servicesDisabled);
      // The resumed capture re-checked services and stopped again.
      expect(service.captureCount, 0);
    });

    test('does not resume a capture superseded by a reset while away',
        () async {
      final service = FakeLocationService(enabled: false);
      final container = createContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(locationControllerProvider.notifier);

      await controller.captureLocation();
      final opening = controller.openLocationSettings();
      controller.reset();
      service.enabled = true;
      await opening;

      // The session ended while the user was in settings; nothing resumes.
      expect(container.read(locationControllerProvider).status,
          LocationStatus.idle);
    });
  });
}