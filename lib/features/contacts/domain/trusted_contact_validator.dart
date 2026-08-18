import '../../../core/result/result.dart';
import 'contact_failures.dart';
import 'phone_number.dart';
import 'trusted_contact.dart';
import 'trusted_contacts_limits.dart';

/// A validated contact input with trimmed name and normalized phone number.
final class ContactDraft {
  const ContactDraft({required this.name, required this.phoneNumber});

  final String name;
  final String phoneNumber;
}

/// Domain rules for trusted-contact input and collections.
class TrustedContactValidator {
  const TrustedContactValidator();

  static const int maxNameLength = 50;

  /// Validates raw user input and returns a normalized [ContactDraft].
  ///
  /// The name is trimmed; the phone number is normalized to its canonical
  /// digits-only form. Failures identify the offending field.
  Result<ContactDraft> validateDraft({
    required String name,
    required String phoneNumber,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return Err(
        InvalidContactFailure(field: 'name', message: 'Enter a name.'),
      );
    }
    if (trimmedName.length > maxNameLength) {
      return Err(
        InvalidContactFailure(
          field: 'name',
          message: 'Name must be $maxNameLength characters or fewer.',
        ),
      );
    }
    if (!PhoneNumber.isValid(phoneNumber)) {
      return Err(
        InvalidContactFailure(
          field: 'phone',
          message: 'Enter a valid phone number (7–15 digits).',
        ),
      );
    }
    return Ok(ContactDraft(name: trimmedName, phoneNumber: PhoneNumber.normalize(phoneNumber)));
  }

  /// Whether [phoneNumber] (already normalized) belongs to another contact.
  bool hasDuplicatePhone(
    List<TrustedContact> contacts,
    String phoneNumber, {
    String? excludeId,
  }) {
    return contacts.any(
      (contact) =>
          contact.id != excludeId && contact.phoneNumber == phoneNumber,
    );
  }

  /// Whether adding one more contact would exceed the maximum.
  bool isAtLimit(int currentCount) => currentCount >= TrustedContactsLimits.max;

  /// Whether the collection's priorities form a contiguous `1..n` sequence.
  bool hasValidPrioritySequence(List<TrustedContact> contacts) {
    final expected = {for (var i = 1; i <= contacts.length; i++) i};
    final actual = {for (final contact in contacts) contact.priority};
    if (actual.length != expected.length) return false;
    return actual.containsAll(expected);
  }

  /// Returns a copy of [contacts] with contiguous priorities `1..n`,
  /// preserving their relative order.
  List<TrustedContact> renormalizePriorities(List<TrustedContact> contacts) {
    return [
      for (final (index, contact) in contacts.indexed)
        contact.copyWith(priority: index + 1),
    ];
  }
}
