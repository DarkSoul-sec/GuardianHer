import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/contacts/domain/contact_failures.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact.dart';
import 'package:guardianher/features/contacts/domain/trusted_contact_validator.dart';
import 'package:guardianher/features/contacts/domain/trusted_contacts_limits.dart';

void main() {
  const validator = TrustedContactValidator();

  TrustedContact contact(String id, String phone, int priority) {
    return TrustedContact(
      id: id,
      name: 'Name $id',
      phoneNumber: phone,
      priority: priority,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  group('validateDraft', () {
    test('accepts valid input and normalizes the phone number', () {
      final result = validator.validateDraft(
        name: '  Mom  ',
        phoneNumber: '+91 12345 67890',
      );
      expect(result, isA<Ok>());
      final draft = (result as Ok).value;
      expect(draft.name, 'Mom');
      expect(draft.phoneNumber, '911234567890');
    });

    test('rejects a blank name', () {
      final result = validator.validateDraft(
        name: '   ',
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      final failure = (result as Err).failure;
      expect(failure, isA<InvalidContactFailure>());
      expect((failure as InvalidContactFailure).field, 'name');
    });

    test('rejects an over-long name', () {
      final result = validator.validateDraft(
        name: 'a' * (TrustedContactValidator.maxNameLength + 1),
        phoneNumber: '911234567890',
      );
      expect(result, isA<Err>());
      expect((result as Err).failure, isA<InvalidContactFailure>());
    });

    test('rejects an invalid phone number', () {
      final result = validator.validateDraft(
        name: 'Mom',
        phoneNumber: '123',
      );
      expect(result, isA<Err>());
      final failure = (result as Err).failure;
      expect(failure, isA<InvalidContactFailure>());
      expect((failure as InvalidContactFailure).field, 'phone');
    });
  });

  group('duplicate detection', () {
    test('detects a duplicate phone number', () {
      final contacts = [contact('1', '911234567890', 1)];
      expect(
        validator.hasDuplicatePhone(contacts, '911234567890'),
        isTrue,
      );
    });

    test('ignores the contact being edited itself', () {
      final contacts = [contact('1', '911234567890', 1)];
      expect(
        validator.hasDuplicatePhone(contacts, '911234567890', excludeId: '1'),
        isFalse,
      );
    });

    test('detects a duplicate against another contact during edit', () {
      final contacts = [
        contact('1', '911234567890', 1),
        contact('2', '919876543210', 2),
      ];
      expect(
        validator.hasDuplicatePhone(contacts, '911234567890', excludeId: '2'),
        isTrue,
      );
    });
  });

  group('max contacts', () {
    test('limit is 5 and isAtLimit reflects it', () {
      expect(TrustedContactsLimits.max, 5);
      expect(validator.isAtLimit(4), isFalse);
      expect(validator.isAtLimit(5), isTrue);
      expect(validator.isAtLimit(6), isTrue);
    });
  });

  group('priority normalization', () {
    test('renormalizePriorities produces a contiguous 1..n sequence', () {
      final contacts = [
        contact('a', '1', 3),
        contact('b', '2', 1),
        contact('c', '3', 2),
      ];
      final renormalized = validator.renormalizePriorities(contacts);
      expect(renormalized.map((c) => c.priority).toList(), [1, 2, 3]);
      expect(renormalized.map((c) => c.id).toList(), ['a', 'b', 'c']);
    });

    test('hasValidPrioritySequence accepts contiguous priorities', () {
      final contacts = [
        contact('a', '1', 1),
        contact('b', '2', 2),
        contact('c', '3', 3),
      ];
      expect(validator.hasValidPrioritySequence(contacts), isTrue);
    });

    test('hasValidPrioritySequence rejects gaps and duplicates', () {
      expect(
        validator.hasValidPrioritySequence([
          contact('a', '1', 1),
          contact('b', '2', 3),
        ]),
        isFalse,
      );
      expect(
        validator.hasValidPrioritySequence([
          contact('a', '1', 1),
          contact('b', '2', 1),
        ]),
        isFalse,
      );
      expect(validator.hasValidPrioritySequence([]), isTrue);
    });
  });
}