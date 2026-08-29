import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/application/contacts_controller.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/application/contacts_state.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

/// A [ContactsController] that returns a fixed contact list without touching
/// storage.
class StubContactsController extends ContactsController {
  StubContactsController(this.contacts);

  final List<TrustedContact> contacts;

  @override
  ContactsState build() => ContactsLoaded(contacts: contacts);
}

final _alice = TrustedContact.create(
  name: 'Alice',
  phoneNumber: '15551234567',
  priority: 1,
);

void main() {
  Future<void> pumpActiveSos(
    WidgetTester tester, {
    required ProviderContainer container,
    required FakeSosTimer timer,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SosScreen()),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'SOS'));
    await tester.pump();
    timer.fireComplete();
    await tester.pump();
  }

  group('SosScreen active actions', () {
    testWidgets('shows contacts with masked numbers and Call/Message buttons',
        (tester) async {
      final timer = FakeSosTimer();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);

      expect(find.text('SOS ACTIVE'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      // The full number is masked; only the last four digits are visible.
      expect(find.text('•••••••4567'), findsOneWidget);
      expect(find.textContaining('15551234567'), findsNothing);
      expect(find.byTooltip('Call Alice'), findsOneWidget);
      expect(find.byTooltip('Message Alice'), findsOneWidget);
      expect(find.text('Call emergency'), findsOneWidget);
      expect(find.text('End SOS'), findsOneWidget);
    });

    testWidgets('tapping Call opens the dialer and reports it truthfully',
        (tester) async {
      final timer = FakeSosTimer();
      final call = FakeCallService();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(call),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);

      await tester.tap(find.byTooltip('Call Alice'));
      await tester.pump();

      expect(call.dialedNumbers, ['15551234567']);
      expect(find.text('Dialer opened.'), findsOneWidget);
    });

    testWidgets('tapping Message opens the SMS composer with the generic body',
        (tester) async {
      final timer = FakeSosTimer();
      final sms = FakeSmsService();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(sms),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);

      await tester.tap(find.byTooltip('Message Alice'));
      await tester.pump();

      expect(sms.opened, hasLength(1));
      expect(sms.opened.single.phoneNumber, '15551234567');
      expect(sms.opened.single.body, contains('automated message'));
      expect(find.text('SMS composer opened.'), findsOneWidget);
    });

    testWidgets('Call emergency dials the emergency services number',
        (tester) async {
      final timer = FakeSosTimer();
      final call = FakeCallService();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(call),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);

      await tester.tap(find.text('Call emergency'));
      await tester.pump();

      expect(call.dialedNumbers, ['112']);
      expect(find.text('Dialer opened.'), findsOneWidget);
    });

    testWidgets('denied notification permission is surfaced but SOS stays up',
        (tester) async {
      final timer = FakeSosTimer();
      final notification = FakeNotificationService()
        ..permissionResult = const Ok(false);
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider.overrideWithValue(notification),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);

      expect(find.text('SOS ACTIVE'), findsOneWidget);
      expect(find.textContaining('Notifications unavailable'), findsOneWidget);
      expect(find.textContaining('Vibration alerting'), findsOneWidget);
      expect(notification.showActiveCalls, 0);
    });

    testWidgets('an empty contact list explains how to add contacts',
        (tester) async {
      final timer = FakeSosTimer();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);

      expect(
        find.textContaining('No trusted contacts yet'),
        findsOneWidget,
      );
    });

    testWidgets('an active SOS reports the best-effort location status',
        (tester) async {
      final timer = FakeSosTimer();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);
      await tester.pump();

      // The location capture resolves best-effort while SOS stays active.
      expect(find.text('SOS ACTIVE'), findsOneWidget);
      expect(find.text('Location captured'), findsOneWidget);
    });

    testWidgets('a timed-out location never affects the active SOS',
        (tester) async {
      final timer = FakeSosTimer();
      final container = createContainer(
        overrides: [
          sosTimerProvider.overrideWithValue(timer),
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider
              .overrideWithValue(() => SosEventId(testSosEventId)),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          locationServiceProvider.overrideWithValue(
            FakeLocationService(failure: const LocationTimeoutFailure()),
          ),
          contactsControllerProvider
              .overrideWith(() => StubContactsController([_alice])),
        ],
      );
      addTearDown(container.dispose);

      await pumpActiveSos(tester, container: container, timer: timer);
      await tester.pump();

      expect(find.text('SOS ACTIVE'), findsOneWidget);
      expect(find.text("Couldn't get your current location"),
          findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('End SOS'), findsOneWidget);

      // End the session so the pending location retry is cancelled before the
      // test ends (no dangling timers).
      container.read(sosControllerProvider.notifier).cancelSos();
      await tester.pump();
      timer.fireComplete();
      await tester.pump();
    });
  });
}