import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/application/contacts_providers.dart';
import 'package:guardianher/features/contacts/application/contacts_state.dart';
import 'package:guardianher/features/contacts/data/contacts_repository_impl.dart';
import 'package:guardianher/features/contacts/domain/contact_failures.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/contacts/domain/trusted_contacts_limits.dart';

import '../../helpers/fakes.dart';
import 'contacts_test_fakes.dart';

void main() {
  ProviderContainer container({required FakeSecureStorageService storage}) {
    return createContainer(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ],
    );
  }

  Future<void> settle(ProviderContainer c) async {
    c.read(contactsControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await c.pump();
  }

  Future<TrustedContact> add(
    ProviderContainer c,
    String name,
    String phone,
  ) async {
    final result = await c
        .read(contactsControllerProvider.notifier)
        .addContact(name: name, phoneNumber: phone);
    expect(result, isA<Ok>(), reason: 'expected $name to be added');
    await settle(c);
    return (result as Ok<TrustedContact>).value;
  }

  ContactsLoaded loaded(ProviderContainer c) {
    final state = c.read(contactsControllerProvider);
    expect(state, isA<ContactsLoaded>());
    return state as ContactsLoaded;
  }

  group('ContactsController', () {
    test('initial load exposes an empty loaded state', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      expect(loaded(c).contacts, isEmpty);
    });

    test('successful add persists and reloads the list', () async {
      final storage = FakeSecureStorageService();
      final c = container(storage: storage);
      addTearDown(c.dispose);
      await settle(c);

      final contact = await add(c, 'Mom', '+91 12345 67890');

      expect(contact.priority, 1);
      expect(contact.phoneNumber, '911234567890');
      expect(loaded(c).contacts.single.name, 'Mom');
      expect(await storage.read(ContactsStorageKeys.contacts), contains('911234567890'));
    });

    test('failed add reports invalid input and keeps the list', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(contactsControllerProvider.notifier)
          .addContact(name: '   ', phoneNumber: '911234567890');
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<InvalidContactFailure>());
      expect(loaded(c).contacts, isEmpty);
    });

    test('duplicate add is rejected', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      await add(c, 'Mom', '+911234567890');
      final result = await c
          .read(contactsControllerProvider.notifier)
          .addContact(name: 'Dad', phoneNumber: '911234567890');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<DuplicateContactFailure>());
      expect(loaded(c).contacts, hasLength(1));
    });

    test('rejects adding beyond the maximum', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      for (var i = 1; i <= TrustedContactsLimits.max; i++) {
        await add(c, 'C$i', '1000000$i');
      }
      final result = await c
          .read(contactsControllerProvider.notifier)
          .addContact(name: 'Extra', phoneNumber: '19999999999');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<MaxContactsReachedFailure>());
      expect(loaded(c).contacts, hasLength(TrustedContactsLimits.max));
    });

    test('successful edit preserves id and updates the list', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      final mom = await add(c, 'Mom', '+911234567890');
      final result = await c
          .read(contactsControllerProvider.notifier)
          .updateContact(id: mom.id, name: 'Mother', phoneNumber: '911234567890');

      expect(result, isA<Ok>());
      final updated = (result as Ok<TrustedContact>).value;
      expect(updated.id, mom.id);
      expect(updated.name, 'Mother');
      expect(loaded(c).contacts.single.name, 'Mother');
    });

    test('duplicate during edit is rejected', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      final mom = await add(c, 'Mom', '+911234567890');
      final dad = await add(c, 'Dad', '+919876543210');

      final result = await c
          .read(contactsControllerProvider.notifier)
          .updateContact(id: dad.id, name: 'Dad', phoneNumber: mom.phoneNumber);
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<DuplicateContactFailure>());

      final ownNumber = await c
          .read(contactsControllerProvider.notifier)
          .updateContact(id: mom.id, name: 'Mom', phoneNumber: mom.phoneNumber);
      expect(ownNumber, isA<Ok>());
    });

    test('successful delete removes the contact and reorders priorities', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      final a = await add(c, 'A', '9111111111');
      final b = await add(c, 'B', '9222222222');
      await add(c, 'C', '9333333333');

      final result = await c
          .read(contactsControllerProvider.notifier)
          .deleteContact(b.id);
      expect(result, isA<Ok>());

      final contacts = loaded(c).contacts;
      expect(contacts.map((c) => c.id).toList(), [a.id, contacts.last.id]);
      expect(contacts.map((c) => c.priority).toList(), [1, 2]);
    });

    test('delete of a missing contact fails', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(contactsControllerProvider.notifier)
          .deleteContact('nope');
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<ContactNotFoundFailure>());
    });

    test('reorder re-assigns priorities', () async {
      final c = container(storage: FakeSecureStorageService());
      addTearDown(c.dispose);
      await settle(c);

      final a = await add(c, 'A', '9111111111');
      final b = await add(c, 'B', '9222222222');
      final d = await add(c, 'C', '9333333333');

      final result = await c
          .read(contactsControllerProvider.notifier)
          .reorderContacts([d.id, a.id, b.id]);
      expect(result, isA<Ok>());

      final contacts = loaded(c).contacts;
      expect(contacts.map((c) => c.id).toList(), [d.id, a.id, b.id]);
      expect(contacts.map((c) => c.priority).toList(), [1, 2, 3]);
    });

    test('storage failure on load surfaces an error state', () async {
      final c = container(storage: FlakySecureStorage()..failRead = true);
      addTearDown(c.dispose);
      await settle(c);

      final state = c.read(contactsControllerProvider);
      expect(state, isA<ContactsError>());
      expect((state as ContactsError).failure, isA<ContactStorageFailure>());
    });

    test('storage failure on save keeps the loaded list', () async {
      final storage = FlakySecureStorage();
      final c = container(storage: storage);
      addTearDown(c.dispose);
      await settle(c);

      await add(c, 'Mom', '+911234567890');
      storage.failWrite = true;

      final result = await c
          .read(contactsControllerProvider.notifier)
          .addContact(name: 'Dad', phoneNumber: '+919876543210');
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<ContactStorageFailure>());

      final contacts = loaded(c).contacts;
      expect(contacts, hasLength(1));
      expect(contacts.single.name, 'Mom');
      expect(loaded(c).saving, isFalse);
    });
  });
}