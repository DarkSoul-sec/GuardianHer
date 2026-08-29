import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/check_in/application/check_in_execution_service.dart';
import 'package:guardianher/features/check_in/domain/check_in_delivery_status.dart';
import 'package:guardianher/features/check_in/domain/check_in_interval.dart';
import 'package:guardianher/features/check_in/domain/check_in_settings.dart';
import 'package:guardianher/features/contacts/domain/contacts_repository.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/location/domain/location_point.dart';

import '../../../helpers/fakes.dart';

/// Fixed contacts repository for execution-service tests.
class StubContactsRepository implements ContactsRepository {
  StubContactsRepository(this.contacts);

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

  final fixedNow = DateTime.utc(2026, 8, 20, 10);

  late FakeCheckInSettingsRepository settingsRepo;
  late FakeLocationService location;
  late FakeCheckInMessageSender sender;
  late FakeCheckInScheduler scheduler;
  late bool sosActive;

  CheckInExecutionSeams buildSeams({StubContactsRepository? contacts}) {
    return CheckInExecutionSeams(
      settingsRepository: settingsRepo,
      locationService: location,
      messageSender: sender,
      contactsRepository: contacts ?? StubContactsRepository([contact]),
      now: () => fixedNow,
      isSosActive: () => sosActive,
      scheduleNextExecution: scheduler.scheduleExecution,
    );
  }

  void enableDefaultSettings({List<String>? recipients}) {
    settingsRepo = FakeCheckInSettingsRepository(
      CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes60,
        recipientContactIds: recipients ?? [contact.id],
        lastAcknowledgedAt: fixedNow,
      ),
    );
  }

  setUp(() {
    sosActive = false;
    location = FakeLocationService();
    sender = FakeCheckInMessageSender();
    scheduler = FakeCheckInScheduler();
    enableDefaultSettings();
  });

  group('runScheduledCheckIn', () {
    test('disabled config runs nothing', () async {
      settingsRepo = FakeCheckInSettingsRepository(CheckInSettings.initial);
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.disabled);
      expect(location.captureCount, 0);
      expect(sender.sent, isEmpty);
      expect(scheduler.executionsScheduled, isEmpty);
    });

    test('no recipients records the reason without capturing', () async {
      enableDefaultSettings(recipients: const []);
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.noRecipients);
      expect(settingsRepo.saved.lastAttemptAt, fixedNow);
      expect(location.captureCount, 0);
    });

    test('SOS skips the run entirely and reschedules', () async {
      sosActive = true;
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.skippedForSos);
      expect(location.captureCount, 0);
      expect(sender.sent, isEmpty);
      expect(scheduler.executionsScheduled, hasLength(1));
      expect(settingsRepo.saved.nextScheduledAt, isNotNull);
    });

    test('fresh capture records success and hands off the message', () async {
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.locationCaptured);
      expect(settingsRepo.saved.lastSuccessfulLocationAt, fixedNow);
      expect(scheduler.executionsScheduled, hasLength(1));
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single.body, contains('My location'));
      expect(sender.sent.single.recipientPhoneNumbers, ['919876543210']);
    });

    test('stale fallback is labeled stale and never counts as fresh',
        () async {
      location.point = LocationPoint(
        latitude: 1,
        longitude: 2,
        accuracyMeters: 50,
        capturedAt: fixedNow.subtract(const Duration(hours: 1)),
        isStale: true,
      );
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.staleOnly);
      expect(settingsRepo.saved.lastSuccessfulLocationAt, isNull);
      expect(sender.sent.single.body, contains('LAST KNOWN'));
      expect(scheduler.executionsScheduled, hasLength(1));
    });

    test('services disabled still composes and keeps cadence alive',
        () async {
      location.failure = const LocationServicesDisabledFailure();
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.servicesDisabled);
      expect(
        sender.sent.single.body,
        contains('could not share my location'),
      );
      expect(scheduler.executionsScheduled, hasLength(1));
    });

    test('permission missing maps to permissionDenied', () async {
      location.failure = const LocationPermissionMissingFailure();
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.permissionDenied);
      expect(scheduler.executionsScheduled, hasLength(1));
    });

    test('timeout maps to timeout status', () async {
      location.failure = const LocationTimeoutFailure();
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.timeout);
    });

    test('unavailable maps to locationUnavailable', () async {
      location.failure = const LocationUnavailableFailure();
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.locationUnavailable);
    });

    test('sender failure records communicationFailed; cadence continues',
        () async {
      sender.failSending = true;
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.communicationFailed);
      expect(settingsRepo.saved.lastSuccessfulLocationAt, fixedNow);
      expect(scheduler.executionsScheduled, hasLength(1));
    });

    test('deleted recipient ids short-circuit to noRecipients', () async {
      final outcome = await runScheduledCheckIn(
        buildSeams(contacts: StubContactsRepository(const [])),
      );
      expect(outcome.status, CheckInExecutionStatus.noRecipients);
      expect(sender.sent, isEmpty);
    });

    test('failed rescheduling marks the whole run schedulerFailed', () async {
      scheduler.failScheduling = true;
      final outcome = await runScheduledCheckIn(buildSeams());
      expect(outcome.status, CheckInExecutionStatus.schedulerFailed);
      expect(outcome.savedSettings.nextScheduledAt, isNull);
    });
  });
}
