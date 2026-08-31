import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/platform/emergency_sms_bridge.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/domain/contacts_repository.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/location/domain/location_failures.dart';
import 'package:guardianher/features/sos/application/emergency_orchestrator.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

/// Yields to the event loop so chained async effect calls are flushed.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A simple in-memory contacts repository for tests.
class _FakeContactsRepository implements ContactsRepository {
  _FakeContactsRepository([List<TrustedContact>? contacts])
      : _contacts = contacts ?? [];

  List<TrustedContact> _contacts;

  @override
  Future<Result<List<TrustedContact>>> loadContacts() async =>
      Ok(_contacts);

  @override
  Future<Result<TrustedContact>> addContact({
    required String name,
    required String phoneNumber,
    String? email,
    bool isEmergencyContact = true,
  }) async {
    final contact = TrustedContact.create(
      name: name,
      phoneNumber: phoneNumber,
      priority: _contacts.length + 1,
      email: email,
      isEmergencyContact: isEmergencyContact,
    );
    _contacts = [..._contacts, contact];
    return Ok(contact);
  }

  @override
  Future<Result<TrustedContact>> updateContact({
    required String id,
    required String name,
    required String phoneNumber,
    String? email,
    bool isEmergencyContact = true,
  }) async => Err(const UnexpectedFailure());

  @override
  Future<Result<void>> deleteContact(String id) async => const Ok(null);

  @override
  Future<Result<List<TrustedContact>>> reorderContacts(
    List<String> orderedIds,
  ) async => Ok(_contacts);
}

TrustedContact _contact({
  String name = 'Alice',
  String phone = '+15551234567',
  int priority = 1,
}) =>
    TrustedContact.create(
      name: name,
      phoneNumber: phone,
      priority: priority,
    );

void main() {
  group('EmergencyOrchestrator', () {
    test('starts in idle state', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.phase, EmergencyPhase.idle);
      expect(state.incidentId, isNull);
      expect(state.guardians, isEmpty);
    });

    test('activates when SOS becomes active', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge();
      final location = FakeLocationService(
        point: testLocationPoint,
      );

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);

      // Register the orchestrator.
      container.read(emergencyOrchestratorProvider);

      // Start SOS with zero countdown.
      container.read(sosControllerProvider.notifier).startSos();
      await settle();

      // SOS should be active now.
      final sosState = container.read(sosControllerProvider);
      expect(sosState, isA<SosActive>());

      // The orchestrator is async; give it time to process.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.phase, EmergencyPhase.active);
      expect(state.incidentId, isNotNull);
      expect(state.guardians, hasLength(1));

      // Native service was called.
      expect(bridge.startCalls, 1);
    });

    test('delegates SMS to native bridge with all guardians', () async {
      final contacts = _FakeContactsRepository([
        _contact(name: 'Alice', phone: '+15551111111', priority: 1),
        _contact(name: 'Bob', phone: '+15552222222', priority: 2),
        _contact(name: 'Carol', phone: '+15553333333', priority: 3),
      ]);
      final bridge = FakeNativeEmergencySmsBridge();

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.guardians, hasLength(3));
      expect(bridge.startCalls, 1);
      expect(
        bridge.lastStartGuardianIds,
        unorderedEquals(contacts._contacts.map((contact) => contact.id)),
      );
      expect(bridge.lastStartSmsBody, contains('SOS ALERT'));

      // Wait for the native bridge to emit completion.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await settle();
    });

    test('GPS timeout sends SMS without location', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge();
      // Location always fails.
      final location = FakeLocationService(
        enabled: false,
        failure: const LocationServicesDisabledFailure(),
      )..openLocationSettingsResult = false;

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      // The settings launch is declined, so the native SMS path must still
      // receive the emergency without a location fix.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.phase, EmergencyPhase.active);
      expect(state.locationAcquired, isFalse);
      expect(state.guardians, hasLength(1));
      expect(bridge.startCalls, 1);
      // SMS body should mention location unavailable.
      expect(bridge.lastStartSmsBody, contains('Location currently unavailable'));
    });

    test('empty contacts list reports error', () async {
      final contacts = _FakeContactsRepository([]);
      final bridge = FakeNativeEmergencySmsBridge();

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.errorMessage, contains('No emergency contacts'));
      expect(bridge.startCalls, 0);
    });

    test('SMS permission denied shows error and does not send', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge()
        ..smsPermissionGranted = false;

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.errorMessage, contains('SMS permission not granted'));
      expect(bridge.startCalls, 0);
    });

    test('resets to idle when SOS ends', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge();
      final timer = FakeSosTimer();

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
          sosTimerProvider.overrideWithValue(timer),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      // Cancel SOS.
      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();

      timer.fireComplete();
      await settle();

      container.read(sosControllerProvider.notifier).resetSos();
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.phase, EmergencyPhase.idle);
      expect(state.incidentId, isNull);
    });

    test('prevents duplicate emergency activation', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge();

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      // Second startSos should be rejected by the state machine.
      container.read(sosControllerProvider.notifier).startSos();
      await settle();

      // Native bridge should only be called once.
      expect(bridge.startCalls, 1);
    });

    test('includes location URL when GPS succeeds', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge();
      final location = FakeLocationService(
        point: testLocationPoint,
      );

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      final state = container.read(emergencyOrchestratorProvider);
      expect(state.locationAcquired, isTrue);
      expect(state.locationUrl, contains('maps.google.com'));
      expect(bridge.lastStartSmsBody, contains('maps.google.com'));
    });

    test('includes battery percentage in SMS body', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge()
        ..batteryPercentage = 42;

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      expect(bridge.lastStartSmsBody, contains('Battery: 42%'));
    });

    test('cancels native emergency when SOS ends', () async {
      final contacts = _FakeContactsRepository([_contact()]);
      final bridge = FakeNativeEmergencySmsBridge()..autoComplete = false;
      final timer = FakeSosTimer();

      final container = createContainer(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contacts),
          nativeEmergencySmsBridgeProvider.overrideWithValue(bridge),
          sosTimerProvider.overrideWithValue(timer),
        ],
      );
      addTearDown(container.dispose);

      container.read(emergencyOrchestratorProvider);
      container.read(sosControllerProvider.notifier).startSos();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle();

      // Cancel SOS.
      container.read(sosControllerProvider.notifier).cancelSos();
      await settle();

      timer.fireComplete();
      await settle();

      // Native bridge cancel was called.
      expect(bridge.cancelCalls, 1);
    });
  });
}
