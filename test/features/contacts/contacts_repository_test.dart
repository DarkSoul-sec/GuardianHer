import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/data/contacts_repository_impl.dart';
import 'package:guardianher/features/contacts/domain/contact_failures.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/contacts/domain/trusted_contacts_limits.dart';

import '../../helpers/fakes.dart';
import 'contacts_test_fakes.dart';

const _ts = '2026-08-18T10:00:00.000Z';

/// Sentinel type so `contactMap` can omit the optional `email` key entirely
/// (a plain `null` default would serialize an explicit `"email": null`).
class _Absent {
  const _Absent();
}

const Object _absent = _Absent();

void main() {
  final now = DateTime.utc(2026, 8, 18, 10);
  late FakeSecureStorageService storage;
  late SecureStorageContactsRepository repository;

  setUp(() {
    storage = FakeSecureStorageService();
    repository = SecureStorageContactsRepository(
      storage: storage,
      now: () => now,
    );
  });

  Map<String, Object?> contactMap({
    required String id,
    required String name,
    required String phone,
    required int priority,
    String? createdAt,
    String? updatedAt,
    Object? email = _absent,
  }) {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phone,
      if (email != _absent) 'email': email,
      'priority': priority,
      'createdAt': createdAt ?? _ts,
      'updatedAt': updatedAt ?? _ts,
    };
  }

  /// Sentinel distinguishing "omit the key" from an explicit null.
  /// Declared top-level; see [_Absent].

  String document(List<Map<String, Object?>> contacts, {int version = 1}) {
    return jsonEncode({'version': version, 'contacts': contacts});
  }

  Future<void> seed(List<Map<String, Object?>> contacts) {
    return storage.write(
      ContactsStorageKeys.contacts,
      document(contacts),
    );
  }

  group('loadContacts', () {
    test('returns an empty list when nothing is stored', () async {
      final result = await repository.loadContacts();
      expect(result, isA<Ok>());
      expect((result as Ok).value, isEmpty);
    });

    test('returns contacts sorted by priority', () async {
      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 2),
        contactMap(id: 'b', name: 'B', phone: '9222222222', priority: 1),
        contactMap(id: 'c', name: 'C', phone: '9333333333', priority: 3),
      ]);
      final result = await repository.loadContacts();
      final contacts = (result as Ok).value;
      expect(contacts.map((c) => c.id).toList(), ['b', 'a', 'c']);
      expect(contacts.map((c) => c.priority).toList(), [1, 2, 3]);
    });

    test('rejects malformed JSON', () async {
      await storage.write(ContactsStorageKeys.contacts, 'not json {');
      final result = await repository.loadContacts();
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<CorruptedContactDataFailure>());
    });

    test('rejects an unsupported version', () async {
      await storage.write(ContactsStorageKeys.contacts, document([], version: 99));
      final result = await repository.loadContacts();
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<CorruptedContactDataFailure>());
    });

    test('rejects a non-object document and non-list contacts', () async {
      await storage.write(ContactsStorageKeys.contacts, '[1,2,3]');
      expect((await repository.loadContacts()), isA<Err>());

      await storage.write(
        ContactsStorageKeys.contacts,
        jsonEncode({'version': 1, 'contacts': {'a': 1}}),
      );
      expect((await repository.loadContacts()), isA<Err>());
    });

    test('rejects contacts with missing or invalid fields', () async {
      await seed([
        {
          'id': 'a',
          'phoneNumber': '9111111111',
          'priority': 1,
          'createdAt': _ts,
          'updatedAt': _ts,
        },
      ]);
      expect((await repository.loadContacts()), isA<Err>());

      await seed([
        contactMap(id: 'a', name: '   ', phone: '9111111111', priority: 1),
      ]);
      expect((await repository.loadContacts()), isA<Err>());
    });

    test('rejects invalid phone numbers', () async {
      await seed([
        contactMap(id: 'a', name: 'A', phone: '123', priority: 1),
      ]);
      expect((await repository.loadContacts()), isA<Err>());

      await seed([
        contactMap(id: 'a', name: 'A', phone: '+91 12345 67890', priority: 1),
      ]);
      expect((await repository.loadContacts()), isA<Err>());
    });

    test('rejects invalid priorities', () async {
      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 0),
      ]);
      expect((await repository.loadContacts()), isA<Err>());

      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 1),
        contactMap(id: 'b', name: 'B', phone: '9222222222', priority: 3),
      ]);
      expect((await repository.loadContacts()), isA<Err>());
    });

    test('rejects invalid timestamps', () async {
      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 1, createdAt: 'not-a-date'),
      ]);
      expect((await repository.loadContacts()), isA<Err>());

      await seed([
        contactMap(
          id: 'a',
          name: 'A',
          phone: '9111111111',
          priority: 1,
          createdAt: _ts,
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      ]);
      expect((await repository.loadContacts()), isA<Err>());
    });

    test('loads an optional email and tolerates documents without it',
        () async {
      // Old document shape: no email key at all.
      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 1),
      ]);
      final legacy = await repository.loadContacts();
      expect((legacy as Ok).value.single.email, isNull);

      // New shape with a stored address.
      await seed([
        contactMap(
          id: 'a',
          name: 'A',
          phone: '9111111111',
          priority: 1,
          email: 'A@Example.com',
        ),
      ]);
      final modern = await repository.loadContacts();
      expect((modern as Ok).value.single.email, 'a@example.com');
    });

    test('rejects a present-but-invalid email', () async {
      for (final bad in ['not-an-address', 'a@localhost', 42]) {
        await seed([
          contactMap(
            id: 'a',
            name: 'A',
            phone: '9111111111',
            priority: 1,
            email: bad,
          ),
        ]);
        final result = await repository.loadContacts();
        expect(result, isA<Err>(), reason: 'email: $bad');
        expect(
          (result as Err).failure,
          isA<CorruptedContactDataFailure>(),
          reason: 'email: $bad',
        );
      }
    });

    test('rejects duplicate ids', () async {
      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 1),
        contactMap(id: 'a', name: 'B', phone: '9222222222', priority: 2),
      ]);
      final result = await repository.loadContacts();
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<CorruptedContactDataFailure>());
    });

    test('rejects duplicate phone numbers', () async {
      await seed([
        contactMap(id: 'a', name: 'A', phone: '9111111111', priority: 1),
        contactMap(id: 'b', name: 'B', phone: '9111111111', priority: 2),
      ]);
      final result = await repository.loadContacts();
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<CorruptedContactDataFailure>());
    });

    test('surfaces a storage failure when reading fails', () async {
      final flaky = FlakySecureStorage()..failRead = true;
      final repo = SecureStorageContactsRepository(storage: flaky);
      final result = await repo.loadContacts();
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<ContactStorageFailure>());
    });
  });

  group('addContact', () {
    test('adds at the lowest priority and persists normalized data', () async {
      final first = await repository.addContact(
        name: 'Mom',
        phoneNumber: '+91 12345 67890',
      );
      final second = await repository.addContact(
        name: 'Dad',
        phoneNumber: '44 7911 123456',
      );

      expect((first as Ok).value.priority, 1);
      expect((second as Ok).value.priority, 2);
      expect((second as Ok).value.phoneNumber, '447911123456');

      final stored = await storage.read(ContactsStorageKeys.contacts);
      expect(stored, contains('911234567890'));
      expect(stored, contains('447911123456'));
      expect(stored, contains('Mom'));
    });

    test('persists an optional email and round-trips it', () async {
      final added = await repository.addContact(
        name: 'Mom',
        phoneNumber: '+91 12345 67890',
        email: ' Mom@Example.COM ',
      );
      expect((added as Ok).value.email, 'mom@example.com');

      final loaded = await repository.loadContacts();
      expect((loaded as Ok).value.single.email, 'mom@example.com');
    });

    test('updateContact stores, changes and clears the optional email',
        () async {
      final added = await repository.addContact(
        name: 'Mom',
        phoneNumber: '911234567890',
        email: 'mom@example.com',
      );
      final id = (added as Ok).value.id;

      // Change.
      final changed = await repository.updateContact(
        id: id,
        name: 'Mom',
        phoneNumber: '911234567890',
        email: 'new@example.com',
      );
      expect((changed as Ok).value.email, 'new@example.com');

      // Clear (the form always submits the field; empty clears it).
      final cleared = await repository.updateContact(
        id: id,
        name: 'Mom',
        phoneNumber: '911234567890',
        email: '',
      );
      expect((cleared as Ok).value.email, isNull);
    });

    test('rejects duplicate normalized phone numbers', () async {
      await repository.addContact(name: 'Mom', phoneNumber: '+91 12345 67890');
      final result = await repository.addContact(
        name: 'Dad',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<DuplicateContactFailure>());
    });

    test('rejects adding beyond the maximum', () async {
      for (var i = 1; i <= TrustedContactsLimits.max; i++) {
        final result = await repository.addContact(
          name: 'C$i',
          phoneNumber: '1000000$i',
        );
        expect(result, isA<Ok>(), reason: 'contact $i should be accepted');
      }
      final result = await repository.addContact(
        name: 'Extra',
        phoneNumber: '19999999999',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<MaxContactsReachedFailure>());
    });

    test('rejects invalid input', () async {
      expect(
        await repository.addContact(name: '  ', phoneNumber: '911234567890'),
        isA<Err>(),
      );
      expect(
        await repository.addContact(name: 'Mom', phoneNumber: '123'),
        isA<Err>(),
      );
    });

    test('surfaces a storage failure when writing fails', () async {
      final flaky = FlakySecureStorage()..failWrite = true;
      final repo = SecureStorageContactsRepository(storage: flaky);
      final result = await repo.addContact(
        name: 'Mom',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<ContactStorageFailure>());
    });

    test('does not overwrite corrupted data with an empty list', () async {
      await storage.write(ContactsStorageKeys.contacts, 'corrupted {');
      final result = await repository.addContact(
        name: 'Mom',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<CorruptedContactDataFailure>());
      expect(
        await storage.read(ContactsStorageKeys.contacts),
        'corrupted {',
      );
    });
  });

  group('updateContact', () {
    test('preserves id and createdAt and refreshes updatedAt', () async {
      final added = (await repository.addContact(
        name: 'Mom',
        phoneNumber: '911234567890',
      )) as Ok<TrustedContact>;

      final result = await repository.updateContact(
        id: added.value.id,
        name: 'Mother',
        phoneNumber: '+1 555 123 4567',
      );
      final updated = (result as Ok).value;
      expect(updated.id, added.value.id);
      expect(updated.createdAt, added.value.createdAt);
      expect(updated.name, 'Mother');
      expect(updated.phoneNumber, '15551234567');
      expect(updated.updatedAt, now);
    });

    test('allows keeping its own phone number', () async {
      final added = (await repository.addContact(
        name: 'Mom',
        phoneNumber: '911234567890',
      )) as Ok<TrustedContact>;
      final result = await repository.updateContact(
        id: added.value.id,
        name: 'Mother',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Ok>());
    });

    test('rejects adopting another contact phone number', () async {
      await repository.addContact(name: 'Mom', phoneNumber: '911234567890');
      final dad = (await repository.addContact(
        name: 'Dad',
        phoneNumber: '919876543210',
      )) as Ok<TrustedContact>;

      final result = await repository.updateContact(
        id: dad.value.id,
        name: 'Dad',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<DuplicateContactFailure>());
    });

    test('fails for an unknown id', () async {
      final result = await repository.updateContact(
        id: 'nope',
        name: 'Mom',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<ContactNotFoundFailure>());
    });
  });

  group('deleteContact', () {
    test('removes the contact and re-normalizes priorities', () async {
      final a = (await repository.addContact(name: 'A', phoneNumber: '9111111111'))
          as Ok<TrustedContact>;
      final b = (await repository.addContact(name: 'B', phoneNumber: '9222222222'))
          as Ok<TrustedContact>;
      final c = (await repository.addContact(name: 'C', phoneNumber: '9333333333'))
          as Ok<TrustedContact>;

      final result = await repository.deleteContact(b.value.id);
      expect(result, isA<Ok>());

      final contacts = ((await repository.loadContacts()) as Ok).value;
      expect(contacts.map((c) => c.id).toList(), [a.value.id, c.value.id]);
      expect(contacts.map((c) => c.priority).toList(), [1, 2]);
      expect(
        await storage.read(ContactsStorageKeys.contacts),
        isNot(contains('9222222222')),
      );
    });

    test('fails for an unknown id', () async {
      final result = await repository.deleteContact('nope');
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<ContactNotFoundFailure>());
    });
  });

  group('reorderContacts', () {
    test('re-assigns contiguous priorities in the given order', () async {
      final a = (await repository.addContact(name: 'A', phoneNumber: '9111111111'))
          as Ok<TrustedContact>;
      final b = (await repository.addContact(name: 'B', phoneNumber: '9222222222'))
          as Ok<TrustedContact>;
      final c = (await repository.addContact(name: 'C', phoneNumber: '9333333333'))
          as Ok<TrustedContact>;

      final result = await repository.reorderContacts(
        [c.value.id, a.value.id, b.value.id],
      );
      expect(result, isA<Ok>());

      final contacts = ((await repository.loadContacts()) as Ok).value;
      expect(contacts.map((c) => c.id).toList(), [c.value.id, a.value.id, b.value.id]);
      expect(contacts.map((c) => c.priority).toList(), [1, 2, 3]);
    });

    test('fails for a non-permutation of ids', () async {
      final a = (await repository.addContact(name: 'A', phoneNumber: '9111111111'))
          as Ok<TrustedContact>;

      expect(
        await repository.reorderContacts(['missing', a.value.id]),
        isA<Err>(),
      );
      expect(
        await repository.reorderContacts([a.value.id, a.value.id]),
        isA<Err>(),
      );
      expect(
        await repository.reorderContacts(const []),
        isA<Err>(),
      );
    });
  });
}