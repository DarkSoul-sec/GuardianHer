import '../../../core/result/result.dart';
import 'trusted_contact.dart';

/// Persistence contract for trusted emergency contacts.
///
/// The domain defines the interface; the data layer provides the
/// implementation. Business invariants (duplicate phone numbers, maximum
/// count, contiguous priorities, id preservation) are enforced by the
/// implementation using domain rules. Phase 3 SOS consumes this interface.
abstract interface class ContactsRepository {
  /// Loads all trusted contacts ordered by ascending priority.
  ///
  /// Returns `Ok([])` when nothing is stored. Corrupted stored data is
  /// reported as a failure rather than silently returning an empty list.
  Future<Result<List<TrustedContact>>> loadContacts();

  /// Adds a new contact at the lowest priority.
  ///
  /// Fails with [DuplicateContactFailure] for an existing normalized phone
  /// number and [MaxContactsReachedFailure] when the limit is reached.
  Future<Result<TrustedContact>> addContact({
    required String name,
    required String phoneNumber,
  });

  /// Updates the name/phone of an existing contact, preserving its [id] and
  /// [createdAt] and refreshing [TrustedContact.updatedAt].
  ///
  /// Fails with [ContactNotFoundFailure] when [id] is unknown and with
  /// [DuplicateContactFailure] when the new phone number belongs to another
  /// contact.
  Future<Result<TrustedContact>> updateContact({
    required String id,
    required String name,
    required String phoneNumber,
  });

  /// Deletes the contact with [id] and re-normalizes remaining priorities.
  Future<Result<void>> deleteContact(String id);

  /// Reorders contacts to match [orderedIds] and re-assigns contiguous
  /// priorities `1..n`.
  ///
  /// Fails when [orderedIds] is not a permutation of the stored contact ids.
  Future<Result<List<TrustedContact>>> reorderContacts(List<String> orderedIds);
}
