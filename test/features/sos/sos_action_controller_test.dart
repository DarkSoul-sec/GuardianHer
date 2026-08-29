import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/sos/application/sos_actions_state.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/domain/sos_failures.dart';
import 'package:guardianher/features/sos/domain/sos_status.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

/// Yields to the event loop so chained async effect calls (which complete as
/// microtasks) are flushed.
Future<void> settle() => Future<void>.delayed(Duration.zero);

TrustedContact _contact() => TrustedContact.create(
      name: 'Alice',
      phoneNumber: '+15551234567',
      priority: 1,
    );

void main() {
  group('SosActionController effect orchestration', () {
    test('full SOS lifecycle drives vibration and notification side effects',
        () async {
      final vibration = FakeVibrationService();
      final notification = FakeNotificationService();
      final (container: container, timer: timer) = createSosContainer(
        vibration: vibration,
        notification: notification,
      );
      addTearDown(container.dispose);

      // Register the coordinator so it observes every SOS transition.
      container.read(sosActionsControllerProvider);

      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      // Arming requests notification permission exactly once.
      expect(notification.requestPermissionCalls, 1);
      expect(notification.permissionGrantedCalls, 1);
      expect(
        container.read(sosActionsControllerProvider).notificationPermission,
        SosNotificationPermission.granted,
      );

      timer.fireComplete();
      await settle();
      // Activation starts the bounded vibration and shows the alert.
      expect(vibration.playCalls, 1);
      expect(notification.showActiveCalls, 1);
      expect(
        container.read(sosActionsControllerProvider).vibrationStatus,
        SosVibrationStatus.active,
      );
      expect(
        container.read(sosActionsControllerProvider).notificationStatus,
        SosNotificationStatus.active,
      );

      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      // Cancelling stops vibration and swaps to the stopping content.
      expect(vibration.stopCalls, 1);
      expect(notification.showStoppingCalls, 1);
      expect(
        container.read(sosActionsControllerProvider).notificationStatus,
        SosNotificationStatus.stopping,
      );

      timer.fireComplete();
      await settle();
      // Completion removes the notification.
      expect(notification.cancelCalls, 1);

      container.read(sosControllerProvider.notifier).resetSos();
      await settle();
      // Idle cleans up idempotently and resets state for the next session.
      expect(notification.cancelCalls, 2);
      expect(vibration.stopCalls, 2);
      expect(container.read(sosActionsControllerProvider).notificationStatus,
          SosNotificationStatus.unknown);
      expect(container.read(sosActionsControllerProvider).vibrationStatus,
          SosVibrationStatus.idle);

      // A new session requests permission again.
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      expect(notification.requestPermissionCalls, 2);
    });

    test('denied notification permission leaves SOS fully active', () async {
      final notification = FakeNotificationService()
        ..permissionResult = const Ok(false);
      final vibration = FakeVibrationService();
      final (container: container, timer: timer) = createSosContainer(
        notification: notification,
        vibration: vibration,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);

      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      expect(
        container.read(sosActionsControllerProvider).notificationStatus,
        SosNotificationStatus.unavailable,
      );

      timer.fireComplete();
      await settle();
      // The SOS workflow stays active and vibration still runs; only the
      // notification is marked unavailable.
      expect(container.read(sosControllerProvider), isA<SosActive>());
      expect(vibration.playCalls, 1);
      expect(notification.showActiveCalls, 0);
      expect(
        container.read(sosActionsControllerProvider).notificationStatus,
        SosNotificationStatus.unavailable,
      );
      expect(
        container.read(sosActionsControllerProvider).notificationPermission,
        SosNotificationPermission.denied,
      );
    });

    test('permission request failure marks notifications unavailable',
        () async {
      final notification = FakeNotificationService()
        ..requestResult = const Err(NotificationPermissionDeniedFailure());
      final (container: container, timer: timer) = createSosContainer(
        notification: notification,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      expect(
        container.read(sosActionsControllerProvider).notificationStatus,
        SosNotificationStatus.unavailable,
      );
      expect(notification.permissionGrantedCalls, 0);

      timer.fireComplete();
      await settle();
      expect(container.read(sosControllerProvider), isA<SosActive>());
    });

    test('failed vibration does not stop activation or notification',
        () async {
      final vibration = FakeVibrationService()
        ..playResult = const Err(VibrationUnavailableFailure());
      final notification = FakeNotificationService();
      final (container: container, timer: timer) = createSosContainer(
        vibration: vibration,
        notification: notification,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      expect(container.read(sosControllerProvider), isA<SosActive>());
      expect(
        container.read(sosActionsControllerProvider).vibrationStatus,
        SosVibrationStatus.failed,
      );
      expect(notification.showActiveCalls, 1);
    });

    test('re-activation while already active does not duplicate effects',
        () async {
      final vibration = FakeVibrationService();
      final notification = FakeNotificationService();
      final (container: container, timer: timer) = createSosContainer(
        vibration: vibration,
        notification: notification,
      );
      addTearDown(container.dispose);

      final controller = container.read(sosActionsControllerProvider.notifier);
      final event = SosEvent(
        id: SosEventId(testSosEventId),
        startedAt: DateTime(2026, 1, 1, 12),
        status: SosStatus.active,
        countdownDuration: const Duration(seconds: 3),
      );

      await controller.onSosStateChanged(
        const SosIdle(),
        SosActive(event: event),
      );
      expect(vibration.playCalls, 1);
      expect(notification.showActiveCalls, 1);

      await controller.onSosStateChanged(
        SosActive(event: event),
        SosActive(event: event),
      );
      expect(vibration.playCalls, 1);
      expect(notification.showActiveCalls, 1);
    });

    test('activation captures a current location without blocking SOS',
        () async {
      final (container: container, timer: timer) = createSosContainer();
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      // SOS stays active and the location capture resolves independently.
      expect(container.read(sosControllerProvider), isA<SosActive>());
      expect(
        container.read(locationControllerProvider).status,
        LocationStatus.captured,
      );
      expect(container.read(locationControllerProvider).point,
          testLocationPoint);
    });

    test('a location failure never affects the SOS workflow', () async {
      final location = FakeLocationService(
        failure: const LocationTimeoutFailure(),
      );
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      expect(container.read(sosControllerProvider), isA<SosActive>());
      expect(
        container.read(locationControllerProvider).status,
        LocationStatus.timeout,
      );
    });

    test('returning to idle resets any captured location', () async {
      final (container: container, timer: timer) = createSosContainer();
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();
      expect(
        container.read(locationControllerProvider).status,
        LocationStatus.captured,
      );

      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      timer.fireComplete();
      await settle();
      container.read(sosControllerProvider.notifier).resetSos();
      await settle();

      expect(container.read(locationControllerProvider).status,
          LocationStatus.idle);
      expect(container.read(locationControllerProvider).point, isNull);
    });
  });

  group('SosActionController alert loop', () {
    test('activation delegates the alert to a running shake service', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final vibration = FakeVibrationService();
      final shake = FakeShakeSosService()..startAlertResult = true;
      final (container: container, timer: timer) = createSosContainer(
        vibration: vibration,
        shake: shake,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      // The native service handles the alert; the Flutter side stays quiet.
      expect(shake.startAlertCalls, 1);
      expect(vibration.playCalls, 0);
      expect(
        container.read(sosActionsControllerProvider).vibrationStatus,
        SosVibrationStatus.active,
      );

      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      expect(shake.stopAlertCalls, 1);
      expect(vibration.stopCalls, 1);
      expect(
        container.read(sosActionsControllerProvider).vibrationStatus,
        SosVibrationStatus.idle,
      );

      debugDefaultTargetPlatformOverride = null;
    });

    test(
        'activation falls back to the repeating loop when the shake service '
        'is not running', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final vibration = FakeVibrationService();
      final shake = FakeShakeSosService()..startAlertResult = false;
      final (container: container, timer: timer) = createSosContainer(
        vibration: vibration,
        shake: shake,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      expect(shake.startAlertCalls, 1);
      expect(shake.stopAlertCalls, 0);
      expect(vibration.playCalls, 1);
      expect(
        container.read(sosActionsControllerProvider).vibrationStatus,
        SosVibrationStatus.active,
      );

      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      expect(shake.stopAlertCalls, 0);
      expect(vibration.stopCalls, 1);

      debugDefaultTargetPlatformOverride = null;
    });

    test('re-activation while active never re-engages the alert', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final vibration = FakeVibrationService();
      final shake = FakeShakeSosService()..startAlertResult = true;
      final (container: container, timer: timer) = createSosContainer(
        vibration: vibration,
        shake: shake,
      );
      addTearDown(container.dispose);

      final controller = container.read(sosActionsControllerProvider.notifier);
      final event = SosEvent(
        id: SosEventId(testSosEventId),
        startedAt: DateTime(2026, 1, 1, 12),
        status: SosStatus.active,
        countdownDuration: const Duration(seconds: 3),
      );
      await controller.onSosStateChanged(
        const SosIdle(),
        SosActive(event: event),
      );
      expect(shake.startAlertCalls, 1);

      await controller.onSosStateChanged(
        SosActive(event: event),
        SosActive(event: event),
      );
      expect(shake.startAlertCalls, 1);
      expect(vibration.playCalls, 0);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('SosActionController location context', () {
    test('activation holds the location context and cancellation stops it',
        () async {
      final sosLocation = TestSosLocationService();
      final (container: container, timer: timer) = createSosContainer(
        sosLocation: sosLocation,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      // The location foreground service is up while SOS is active so a fix can
      // be captured with the phone locked / screen off.
      expect(sosLocation.startCalls, 1);
      expect(sosLocation.stopCalls, 0);

      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      expect(sosLocation.stopCalls, 1);
    });

    test('ending the session stops the location context', () async {
      final sosLocation = TestSosLocationService();
      final (container: container, timer: timer) = createSosContainer(
        sosLocation: sosLocation,
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();
      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      timer.fireComplete();
      await settle();
      container.read(sosControllerProvider.notifier).resetSos();
      await settle();

      // Both the cancelling and idle transitions stop the context (idempotent).
      expect(sosLocation.stopCalls, greaterThanOrEqualTo(1));
    });

    test('a failed capture is retried once while SOS stays active', () async {
      final location = FakeLocationService(
        failure: const LocationTimeoutFailure(),
      );
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          locationServiceProvider.overrideWithValue(location),
          sosLocationRetryDelayProvider
              .overrideWithValue(const Duration(milliseconds: 50)),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      expect(
        container.read(locationControllerProvider).status,
        LocationStatus.timeout,
      );
      expect(location.captureCount, 1);

      // The single automatic re-attempt fires after the retry delay.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(location.captureCount, 2);
    });

    test('a successful capture is not retried', () async {
      final location = FakeLocationService();
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          locationServiceProvider.overrideWithValue(location),
          sosLocationRetryDelayProvider
              .overrideWithValue(const Duration(milliseconds: 50)),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(location.captureCount, 1);
    });

    test('activation silently enables location when it is off', () async {
      final location = FakeLocationService(enabled: false)
        ..enableLocationServicesResult = true;
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      expect(location.enableLocationServicesCalls, 1);
      expect(location.openLocationSettingsCount, 0);
      expect(
        container.read(locationControllerProvider).status,
        LocationStatus.captured,
      );
    });

    test('activation opens location settings when it cannot enable silently',
        () async {
      final location = FakeLocationService(enabled: false)
        ..enableLocationServicesResult = false;
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();

      expect(location.enableLocationServicesCalls, 1);
      expect(location.openLocationSettingsCount, greaterThanOrEqualTo(1));
      expect(
        container.read(locationControllerProvider).status,
        LocationStatus.servicesDisabled,
      );
    });

    test('ending SOS before the retry fires cancels it', () async {
      final location = FakeLocationService(
        failure: const LocationTimeoutFailure(),
      );
      final (container: container, timer: timer) = createSosContainer(
        extraOverrides: [
          locationServiceProvider.overrideWithValue(location),
          sosLocationRetryDelayProvider
              .overrideWithValue(const Duration(milliseconds: 50)),
        ],
      );
      addTearDown(container.dispose);

      container.read(sosActionsControllerProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      timer.fireComplete();
      await settle();
      expect(location.captureCount, 1);

      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();
      timer.fireComplete();
      await settle();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(location.captureCount, 1);
    });
  });

  group('SosActionController user actions', () {
    test('callContact opens the dialer with the normalized number', () async {
      final call = FakeCallService();
      final (container: container, timer: timer) = createSosContainer(call: call);
      addTearDown(container.dispose);

      final result = await container
          .read(sosActionsControllerProvider.notifier)
          .callContact(_contact());

      expect(result, isA<Ok<SosActionOutcome>>());
      expect(call.dialedNumbers, ['15551234567']);
      expect((result as Ok<SosActionOutcome>).value.message, 'Dialer opened.');
      expect(result.value.isSuccess, isTrue);
      expect(
        container.read(sosActionsControllerProvider).lastOutcome?.message,
        'Dialer opened.',
      );
    });

    test('messageContact opens the SMS composer with the generic body',
        () async {
      final sms = FakeSmsService();
      final (container: container, timer: timer) = createSosContainer(sms: sms);
      addTearDown(container.dispose);

      final result = await container
          .read(sosActionsControllerProvider.notifier)
          .messageContact(_contact());

      expect(result, isA<Ok<SosActionOutcome>>());
      expect(sms.opened, hasLength(1));
      expect(sms.opened.single.phoneNumber, '15551234567');
      expect(
        sms.opened.single.body,
        'I need help. This is an automated message from GuardianHer. '
        'Please contact me.',
      );
      expect((result as Ok<SosActionOutcome>).value.message, 'SMS composer opened.');
    });

    test('callEmergency dials the configured emergency number', () async {
      final call = FakeCallService();
      final (container: container, timer: timer) = createSosContainer(call: call);
      addTearDown(container.dispose);

      final result = await container
          .read(sosActionsControllerProvider.notifier)
          .callEmergency();

      expect(result, isA<Ok<SosActionOutcome>>());
      expect(call.dialedNumbers, ['112']);
      expect((result as Ok<SosActionOutcome>).value.message, 'Dialer opened.');
    });

    test('invalid contact number is rejected without opening anything',
        () async {
      final call = FakeCallService();
      final (container: container, timer: timer) = createSosContainer(call: call);
      addTearDown(container.dispose);

      final invalid = TrustedContact.create(
        name: 'Bad',
        phoneNumber: '123',
        priority: 1,
      );
      final result = await container
          .read(sosActionsControllerProvider.notifier)
          .callContact(invalid);

      expect(result, isA<Err<SosActionOutcome>>());
      expect((result as Err<SosActionOutcome>).failure, isA<InvalidSosContactFailure>());
      expect(call.dialedNumbers, isEmpty);
    });

    test('invalid emergency number is rejected', () async {
      final call = FakeCallService();
      final (container: container, timer: timer) = createSosContainer(
        call: call,
        extraOverrides: [
          sosEmergencyNumberProvider.overrideWithValue('not-a-number'),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(sosActionsControllerProvider.notifier)
          .callEmergency();

      expect(result, isA<Err<SosActionOutcome>>());
      expect((result as Err<SosActionOutcome>).failure, isA<InvalidSosContactFailure>());
      expect(call.dialedNumbers, isEmpty);
    });

    test('a failed dialer launch yields a truthful failure outcome',
        () async {
      final call = FakeCallService()
        ..result = const Err(NoDialerAvailableFailure());
      final (container: container, timer: timer) = createSosContainer(call: call);
      addTearDown(container.dispose);

      final result = await container
          .read(sosActionsControllerProvider.notifier)
          .callContact(_contact());

      expect(result, isA<Ok<SosActionOutcome>>());
      expect((result as Ok<SosActionOutcome>).value.isSuccess, isFalse);
      expect(result.value.message, contains('Unable to open the dialer'));
    });
  });
}