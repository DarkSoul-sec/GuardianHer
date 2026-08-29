import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/check_in/application/check_in_providers.dart';
import 'package:guardianher/features/check_in/domain/check_in_interval.dart';
import 'package:guardianher/features/check_in/domain/check_in_settings.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/domain/contacts_repository.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';

import '../../../helpers/fakes.dart';
import '../../sos/sos_test_fakes.dart';

/// Contacts repository returning a fixed contact list.
class FixedContactsRepository implements ContactsRepository {
  FixedContactsRepository(this.contacts);

  final List<TrustedContact> contacts;

  @override
  Future<Result<List<TrustedContact>>> loadContacts() async => Ok(contacts);

  @override
  Future<Result<TrustedContact>> addContact({
    required String name,
    required String phoneNumber,
    String? email,
  }) async =>
      const Err(UnexpectedFailure());

  @override
  Future<Result<void>> deleteContact(String id) async =>
      const Err(UnexpectedFailure());

  @override
  Future<Result<List<TrustedContact>>> reorderContacts(
    List<String> orderedIds,
  ) async =>
      const Err(UnexpectedFailure());

  @override
  Future<Result<TrustedContact>> updateContact({
    required String id,
    required String name,
    required String phoneNumber,
    String? email,
  }) async =>
      const Err(UnexpectedFailure());
}

void main() {
  final contact = TrustedContact.create(
    name: 'Anita',
    phoneNumber: '919876543210',
    priority: 1,
  );

  /// Lets the controller's fire-and-forget `build()` load complete.
  Future<void> pump() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  late DateTime now;
  late FakeCheckInSettingsRepository repository;
  late FakeCheckInScheduler scheduler;
  late FakeCheckInMessageSender sender;
  late FakeNotificationService notification;

  final recipients = [contact.id];

  Future<ProviderContainer> create({
    CheckInSettings? initialSettings,
    FakeNotificationService? notificationFake,
    FixedContactsRepository? contactsFake,
  }) async {
    now = DateTime.utc(2026, 1, 1, 12);
    repository = FakeCheckInSettingsRepository(initialSettings);
    scheduler = FakeCheckInScheduler();
    sender = FakeCheckInMessageSender();
    notification = notificationFake ?? FakeNotificationService();
    final container = createContainer(
      overrides: [
        checkInSettingsRepositoryProvider.overrideWithValue(repository),
        checkInSchedulerProvider.overrideWithValue(scheduler),
        checkInMessageSenderProvider.overrideWithValue(sender),
        notificationServiceProvider.overrideWithValue(notification),
        checkInClockProvider.overrideWithValue(() => now),
        contactsRepositoryProvider
            .overrideWithValue(contactsFake ?? FixedContactsRepository([
          contact,
        ])),
      ],
    );
    addTearDown(container.dispose);
    container.read(checkInControllerProvider);
    await pump();
    return container;
  }

  group('CheckInController initial load', () {
    test('starts disabled when nothing is stored', () async {
      final container = await create();
      final state = container.read(checkInControllerProvider);
      expect(state.loaded, isTrue);
      expect(state.settings.enabled, isFalse);
      expect(state.isDue, isFalse);
    });

    test('an enabled timeline with a past acknowledgment is due and escalated',
        () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 125)),
        missedCount: 0,
      );
      final container = await create(initialSettings: settings);
      final state = container.read(checkInControllerProvider);
      expect(state.settings.enabled, isTrue);
      expect(state.missedCount, 1);
      expect(state.isDue, isTrue);
      // Escalation re-notifies immediately (reminder-style) and keeps the
      // execution cadence aligned to the timeline.
      expect(scheduler.scheduled.where((s) => s.missedCount == 1).length, 1);
      expect(scheduler.executionsScheduled, hasLength(1));
    });
  });

  group('CheckInController.enable', () {
    test('refuses to enable without recipients', () async {
      final container = await create();
      final result = await container
          .read(checkInControllerProvider.notifier)
          .enable(interval: CheckInInterval.minutes60, recipientContactIds: const []);
      expect(result, isA<Err>());
      expect(container.read(checkInControllerProvider).settings.enabled, isFalse);
      expect(scheduler.scheduled, isEmpty);
    });

    test('requests notification permission and schedules the first reminder',
        () async {
      final container = await create();
    final result = await container
        .read(checkInControllerProvider.notifier)
        .enable(interval: CheckInInterval.minutes60, recipientContactIds: recipients);
      expect(result, isA<Ok>());
      expect(notification.requestPermissionCalls, 1);
      final state = container.read(checkInControllerProvider);
      expect(state.settings.enabled, isTrue);
      expect(state.settings.interval, CheckInInterval.minutes60);
      expect(state.settings.missedCount, 0);
      expect(scheduler.executionsScheduled, hasLength(1));
      expect(
        scheduler.executionsScheduled.single,
        now.add(const Duration(minutes: 60)),
      );
    });

    test('does not enable when notification permission is denied', () async {
      final denied = FakeNotificationService()
        ..permissionResult = const Ok(false);
      final container = await create(notificationFake: denied);
      final result = await container
          .read(checkInControllerProvider.notifier)
          .enable(interval: CheckInInterval.minutes60, recipientContactIds: recipients);
      expect(result, isA<Err>());
      expect(container.read(checkInControllerProvider).settings.enabled, isFalse);
      expect(scheduler.scheduled, isEmpty);
    });
  });

  group('CheckInController.disable', () {
    test('cancels the pending reminder and turns the feature off', () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now,
      );
      final container = await create(initialSettings: settings);
      final result =
          await container.read(checkInControllerProvider.notifier).disable();
      expect(result, isA<Ok>());
      expect(scheduler.cancelCount, 1);
      final state = container.read(checkInControllerProvider);
      expect(state.settings.enabled, isFalse);
      expect(state.missedCount, 0);
    });
  });

  group('CheckInController.acknowledge', () {
    test('captures location, sends the message and reschedules', () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 60)),
        missedCount: 0,
      );
      final container = await create(initialSettings: settings);
      final result =
          await container.read(checkInControllerProvider.notifier).acknowledge();
      expect(result, isA<Ok>());
      expect(sender.sent, hasLength(1));
      final message = sender.sent.single;
      expect(message.recipientPhoneNumbers, [contact.phoneNumber]);
      expect(message.body, contains('maps.google.com'));
      expect(message.missedCount, 0);
      final state = container.read(checkInControllerProvider);
      expect(state.settings.missedCount, 0);
      expect(state.statusMessage, 'Check-in message opened for sending.');
      expect(
        scheduler.executionsScheduled.last,
        now.add(const Duration(minutes: 60)),
      );
    });

    test('resolves optional contact emails into the message (deduped)',
        () async {
      final anita = TrustedContact.create(
        name: 'Anita',
        phoneNumber: '919876543210',
        priority: 1,
        email: 'anita@example.com',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final ria = TrustedContact.create(
        name: 'Ria',
        phoneNumber: '919812345678',
        priority: 2,
        email: 'ANITA@example.com', // duplicate address, different case
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final noEmail = TrustedContact.create(
        name: 'Sara',
        phoneNumber: '919800000000',
        priority: 3,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: [anita.id, ria.id, noEmail.id],
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 60)),
      );
      final container = await create(
        initialSettings: settings,
        contactsFake:
            FixedContactsRepository([noEmail, ria, anita]), // shuffled order
      );
      final result =
          await container.read(checkInControllerProvider.notifier).acknowledge();
      expect(result, isA<Ok>());
      expect(sender.sent.single.recipientPhoneNumbers,
          [noEmail.phoneNumber, ria.phoneNumber, anita.phoneNumber]);
      expect(sender.sent.single.recipientEmails, ['anita@example.com']);
    });

    test('sends without a location when the fix fails', () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 60)),
      );
      final container = await create(initialSettings: settings);
      container.read(locationServiceProvider);
      // Make the location fake fail.
      final location =
          container.read(locationServiceProvider) as FakeLocationService;
      location.failure = LocationUnavailableFailure();
      final result =
          await container.read(checkInControllerProvider.notifier).acknowledge();
      expect(result, isA<Ok>());
      expect(sender.sent.single.body, contains('could not share my location'));
    });

    test('includes missed-check-in escalation in the message', () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 125)),
        missedCount: 1,
      );
      final container = await create(initialSettings: settings);
      await container.read(checkInControllerProvider.notifier).acknowledge();
      expect(sender.sent.single.missedCount, 1);
      expect(sender.sent.single.body, startsWith('I missed my previous'));
      // Acknowledging clears the missed count.
      expect(container.read(checkInControllerProvider).settings.missedCount, 0);
    });

    test('reports a sender failure without crashing the flow', () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 60)),
      );
      final container = await create(initialSettings: settings);
      sender.failSending = true;
      final result =
          await container.read(checkInControllerProvider.notifier).acknowledge();
      expect(result, isA<Err>());
      final state = container.read(checkInControllerProvider);
      expect(state.statusMessage, contains('messaging'));
    });
  });

  group('CheckInController.refresh', () {
    test('starts the first interval when enabled without a timeline', () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes120,
        recipientContactIds: recipients,
      );
      final container = await create(initialSettings: settings);
      final state = container.read(checkInControllerProvider);
      expect(state.settings.lastAcknowledgedAt, now);
      expect(state.isDue, isFalse);
      expect(scheduler.executionsScheduled.last, now.add(const Duration(minutes: 120)));
    });

    test('escalates and re-notifies once a reminder passes unanswered',
        () async {
      final settings = CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients,
        lastAcknowledgedAt: now.subtract(const Duration(minutes: 60)),
        missedCount: 0,
      );
      final container = await create(initialSettings: settings);
      // Advance well past two skipped intervals.
      now = now.add(const Duration(minutes: 130));
      await container.read(checkInControllerProvider.notifier).refresh();
      final state = container.read(checkInControllerProvider);
      expect(state.missedCount, 2);
      expect(state.isDue, isTrue);
      expect(repository.saved.missedCount, 2);
      expect(
        scheduler.scheduled
            .where((s) => s.missedCount == 2)
            .isNotEmpty,
        isTrue,
      );
    });
  });
}