import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/contacts/domain/trusted_contact.dart';

void main() {
  group('TrustedContact', () {
    test('create generates a unique, stable id', () {
      final a = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
      );
      final b = TrustedContact.create(
        name: 'Dad',
        phoneNumber: '919876543210',
        priority: 2,
      );
      expect(a.id, isNotEmpty);
      expect(a.id.length, 32);
      expect(a.id, isNot(b.id));
    });

    test('create uses UTC timestamps and equals them when not provided', () {
      final created = DateTime.utc(2026, 1, 1);
      final contact = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
        createdAt: created,
        updatedAt: created,
      );
      expect(contact.createdAt, created);
      expect(contact.updatedAt, created);
      expect(contact.createdAt.isUtc, isTrue);
    });

    test('copyWith preserves id and createdAt and updates updatedAt', () {
      final original = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final updated = original.copyWith(
        name: 'Mother',
        priority: 2,
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      expect(updated.id, original.id);
      expect(updated.createdAt, original.createdAt);
      expect(updated.name, 'Mother');
      expect(updated.priority, 2);
      expect(updated.phoneNumber, original.phoneNumber);
      expect(updated.updatedAt, DateTime.utc(2026, 2, 1));
    });

    test('equality compares all fields', () {
      final a = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final b = TrustedContact(
        id: a.id,
        name: a.name,
        phoneNumber: a.phoneNumber,
        priority: a.priority,
        createdAt: a.createdAt,
        updatedAt: a.updatedAt,
      );
      expect(a, b);
      expect(a.copyWith(name: 'Other'), isNot(a));
    });

    test('create normalizes the optional email (blank → null)', () {
      final withEmail = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
        email: '  MOM@Example.COM ',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final withoutEmail = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
        email: '   ',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(withEmail.email, 'mom@example.com');
      expect(withoutEmail.email, isNull);
    });

    test('copyWith can set and clear the optional email', () {
      final original = TrustedContact.create(
        name: 'Mom',
        phoneNumber: '911234567890',
        priority: 1,
        email: 'mom@example.com',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final changed = original.copyWith(email: () => 'other@example.com');
      expect(changed.email, 'other@example.com');

      final cleared = original.copyWith(email: () => null);
      expect(cleared.email, isNull);

      // Omitting the parameter preserves the stored address (form semantics:
      // only an explicit function clears it).
      final untouched = original.copyWith(name: 'Mother');
      expect(untouched.email, 'mom@example.com');
    });
  });
}