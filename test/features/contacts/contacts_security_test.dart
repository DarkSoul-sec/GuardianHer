import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/data/contacts_repository_impl.dart';
import 'package:guardianher/features/contacts/domain/contact_failures.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';

import '../../helpers/fakes.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const GuardianHerApp(),
  );
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_done': true,
    });
  });

  group('contacts security', () {
    testWidgets('contacts are reachable immediately without authentication',
        (tester) async {
      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(
            FakeSecureStorageService(),
          ),
          permissionServiceProvider.overrideWithValue(
            FakePermissionService()
              ..statuses[AppPermission.location] = PermissionStatus.granted
              ..statuses[AppPermission.sms] = PermissionStatus.granted
              ..statuses[AppPermission.notifications] = PermissionStatus.granted,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();

      expect(find.text('Trusted Contacts'), findsOneWidget);
    });

    test('failure messages never leak phone numbers', () {
      const failures = <Failure>[
        DuplicateContactFailure(),
        MaxContactsReachedFailure(),
        ContactNotFoundFailure(),
        CorruptedContactDataFailure(),
        SerializationFailure(),
        ContactStorageFailure(),
      ];
      for (final failure in failures) {
        expect(
          failure.message,
          isNot(contains(RegExp(r'\d{7,}'))),
          reason: '${failure.runtimeType} must not embed phone numbers',
        );
      }
    });

    test('contacts are persisted through secure storage only', () async {
      final storage = FakeSecureStorageService();
      final preferences = FakePreferencesService();
      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          preferencesServiceProvider.overrideWithValue(preferences),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(contactsControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final result = await controller.addContact(
        name: 'Mom',
        phoneNumber: '+911234567890',
      );
      expect(result, isA<Ok<void>>());
      await container.pump();

      expect(await storage.containsKey(ContactsStorageKeys.contacts), isTrue);
      expect(
        await storage.read(ContactsStorageKeys.contacts),
        contains('911234567890'),
      );
      // SharedPreferences must never hold contact data.
      expect(preferences.getKeys(), isEmpty);
    });

    test('contacts survive secure-storage serialization round trip', () async {
      final storage = FakeSecureStorageService();
      final repository = SecureStorageContactsRepository(storage: storage);
      final added = await repository.addContact(
        name: 'Mom',
        phoneNumber: '+911234567890',
      );
      final contact = (added as Ok<TrustedContact>).value;

      final loaded = await repository.loadContacts();
      final contacts = (loaded as Ok<List<TrustedContact>>).value;
      expect(contacts.length, 1);
      expect(contacts.single.id, contact.id);
      expect(contacts.single.phoneNumber, contact.phoneNumber);
    });
  });
}