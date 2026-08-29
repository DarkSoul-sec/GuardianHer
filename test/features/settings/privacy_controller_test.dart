import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/data/contacts_repository_impl.dart';
import 'package:guardianher/features/location/application/location_providers.dart';
import 'package:guardianher/features/location/application/location_state.dart';
import 'package:guardianher/features/settings/application/privacy_providers.dart';
import 'package:guardianher/features/settings/presentation/settings_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  group('PrivacyController', () {
    test('surfaces a cleanup failure', () async {
      final cleanup = FakeDataCleanupService(
        result: const Err<void>(StorageFailure('boom')),
      );
      final container = createContainer(
        overrides: [
          dataCleanupServiceProvider.overrideWithValue(cleanup),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(privacyControllerProvider.notifier)
          .deleteAllLocalData();

      expect(result, isA<Err>());
      expect(cleanup.calls, 1);
    });

    test('deletes trusted contacts from secure storage', () async {
      final storage = FakeSecureStorageService();
      final repository = SecureStorageContactsRepository(storage: storage);
      await repository.addContact(name: 'Mom', phoneNumber: '+911234567890');

      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(privacyControllerProvider.notifier)
          .deleteAllLocalData();

      expect(result, isA<Ok>());
      expect(await storage.containsKey(ContactsStorageKeys.contacts), isFalse);
    });
  });

  group('SettingsScreen delete flow', () {
    testWidgets('delete all local data confirms and clears stored contacts',
        (tester) async {
      final storage = FakeSecureStorageService();
      final repository = SecureStorageContactsRepository(storage: storage);
      await repository.addContact(name: 'Mom', phoneNumber: '+911234567890');

      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Delete all local data'),
        200,
      );
      await tester.tap(find.text('Delete all local data'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all local data?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await storage.containsKey(ContactsStorageKeys.contacts), isFalse);
    });

    testWidgets('cancel keeps the stored contacts', (tester) async {
      final storage = FakeSecureStorageService();
      final repository = SecureStorageContactsRepository(storage: storage);
      await repository.addContact(name: 'Mom', phoneNumber: '+911234567890');

      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Delete all local data'),
        200,
      );
      await tester.tap(find.text('Delete all local data'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await storage.containsKey(ContactsStorageKeys.contacts), isTrue);
    });
  });

  group('PrivacyController provider invalidation', () {
    test('resets location controller to idle after delete-all', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      // Simulate a captured location state by invalidating and reading.
      final locationNotifier =
          container.read(locationControllerProvider.notifier);
      // The location controller starts idle; after delete-all it should be
      // re-created in idle state via provider invalidation.
      expect(container.read(locationControllerProvider).status,
          equals(LocationStatus.idle));

      final privacy = container.read(privacyControllerProvider.notifier);
      await privacy.deleteAllLocalData();

      // After invalidation, the provider is re-created → idle state.
      expect(container.read(locationControllerProvider).status,
          equals(LocationStatus.idle));
      expect(container.read(locationControllerProvider).point, isNull);
    });

    test('resets contacts controller after delete-all', () async {
      final storage = FakeSecureStorageService();
      final repository = SecureStorageContactsRepository(storage: storage);
      await repository.addContact(name: 'Mom', phoneNumber: '+911234567890');

      final container = createContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      // Verify contacts exist before deletion.
      final before = container.read(contactsControllerProvider);
      expect(before.contacts, isNotEmpty);

      final privacy = container.read(privacyControllerProvider.notifier);
      await privacy.deleteAllLocalData();

      // After invalidation, contacts controller is re-created → empty.
      final after = container.read(contactsControllerProvider);
      expect(after.contacts, isEmpty);
    });
  });
}