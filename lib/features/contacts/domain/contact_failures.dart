import '../../../core/error/failures.dart';
import 'trusted_contacts_limits.dart';

/// Base type for trusted-contacts feature failures.
sealed class ContactFailure extends Failure {
  const ContactFailure({
    super.message = 'A contact error occurred.',
    super.code,
  });
}

/// The submitted name or phone number did not pass validation.
///
/// [field] identifies which input was rejected ('name' or 'phone').
final class InvalidContactFailure extends ContactFailure {
  const InvalidContactFailure({
    required this.field,
    super.message = 'Enter valid contact details.',
    super.code = 'invalid_contact',
  });

  final String field;
}

/// A contact with the same normalized phone number already exists.
final class DuplicateContactFailure extends ContactFailure {
  const DuplicateContactFailure({
    super.message = 'This phone number is already a trusted contact.',
    super.code = 'duplicate_contact',
  });
}

/// The contact collection is already at [TrustedContactsLimits.max].
final class MaxContactsReachedFailure extends ContactFailure {
  const MaxContactsReachedFailure({
    super.message = TrustedContactsLimits.maxReachedMessage,
    super.code = 'max_contacts',
  });
}

/// The contact being modified or deleted no longer exists.
final class ContactNotFoundFailure extends ContactFailure {
  const ContactNotFoundFailure({
    super.message = 'This contact no longer exists.',
    super.code = 'contact_not_found',
  });
}

/// Stored contact data is present but invalid and cannot be used safely.
final class CorruptedContactDataFailure extends ContactFailure {
  const CorruptedContactDataFailure({
    super.message = 'Stored contact data is corrupted and cannot be loaded.',
    super.code = 'corrupted_contact_data',
  });
}

/// Contact data could not be encoded into its storage representation.
final class SerializationFailure extends ContactFailure {
  const SerializationFailure({
    super.message = 'Contact data could not be saved.',
    super.code = 'serialization',
  });
}

/// Secure storage could not be read or written.
final class ContactStorageFailure extends ContactFailure {
  const ContactStorageFailure({
    super.message = 'Contacts could not be saved or loaded.',
    super.code = 'contact_storage',
  });
}
