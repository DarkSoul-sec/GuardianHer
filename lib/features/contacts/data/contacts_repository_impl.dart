import 'dart:convert';

import '../../../core/result/result.dart';
import '../../../core/security/secure_storage_service.dart';
import '../domain/contact_failures.dart';
import '../domain/contacts_repository.dart';
import '../domain/phone_number.dart';
import '../domain/trusted_contact.dart';
import '../domain/trusted_contact_validator.dart';

/// Keys used to persist trusted contacts in secure storage.
abstract final class ContactsStorageKeys {
  ContactsStorageKeys._();

  static const contacts = 'trusted_contacts';
}

/// Serialization version of the stored contact document.
///
/// Stays at 1 after Phase 3G: contacts gained an OPTIONAL `email` field, and
/// old documents without it load unchanged (`email == null`), so no migration
/// is required.
const int _contactsDocumentVersion = 1;

/// Stores trusted contacts as a versioned document in Keystore-backed secure
/// storage.
///
/// The whole collection is persisted under a single key as JSON:
///
/// ```json
/// {
///   "version": 1,
///   "contacts": [
///     {
///       "id": "...",
///       "name": "...",
///       "phoneNumber": "...",
///       "email": "someone@example.com" | absent/null,
///       "priority": 1,
///       "createdAt": "2026-08-18T10:00:00.000Z",
///       "updatedAt": "2026-08-18T10:00:00.000Z"
///     }
///   ]
/// }
/// ```
///
/// Stored data is treated as untrusted: malformed JSON, an unsupported
/// version, missing or invalid fields, duplicate ids/phones or non-contiguous
/// priorities are all reported as [CorruptedContactDataFailure] instead of
/// crashing or silently returning an empty list. A present-but-invalid email
/// is likewise corrupted data; an absent one is simply a contact without a
/// fallback address.
class SecureStorageContactsRepository implements ContactsRepository {
  const SecureStorageContactsRepository({
    required this.storage,
    this.validator = const TrustedContactValidator(),
    this.now = DateTime.now,
  });

  final SecureStorageService storage;
  final TrustedContactValidator validator;

  /// Clock used for `createdAt`/`updatedAt` timestamps (injectable for tests).
  final DateTime Function() now;

  @override
  Future<Result<List<TrustedContact>>> loadContacts() async {
    final read = await _read();
    if (read is Err) return read;
    final contacts = List.of((read as Ok<List<TrustedContact>>).value)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return Ok(contacts);
  }

  @override
  Future<Result<TrustedContact>> addContact({
    required String name,
    required String phoneNumber,
    String? email,
    bool isEmergencyContact = true,
  }) async {
    final ContactDraft draft;
    switch (validator.validateDraft(
      name: name,
      phoneNumber: phoneNumber,
      email: email,
    )) {
      case Ok(:final value):
        draft = value;
      case Err(:final failure):
        return Err(failure);
    }

    final read = await _read();
    if (read case Err(:final failure)) return Err(failure);
    final contacts = List.of((read as Ok<List<TrustedContact>>).value);

    if (validator.hasDuplicatePhone(contacts, draft.phoneNumber)) {
      return const Err(DuplicateContactFailure());
    }
    if (validator.isAtLimit(contacts.length)) {
      return const Err(MaxContactsReachedFailure());
    }

    final contact = TrustedContact.create(
      name: draft.name,
      phoneNumber: draft.phoneNumber,
      email: draft.email,
      isEmergencyContact: isEmergencyContact,
      priority: contacts.length + 1,
      createdAt: now(),
      updatedAt: now(),
    );
    contacts.add(contact);

    final saved = await _save(contacts);
    if (saved case Err(:final failure)) return Err(failure);
    return Ok(contact);
  }

  @override
  Future<Result<TrustedContact>> updateContact({
    required String id,
    required String name,
    required String phoneNumber,
    String? email,
    bool isEmergencyContact = true,
  }) async {
    final ContactDraft draft;
    switch (validator.validateDraft(
      name: name,
      phoneNumber: phoneNumber,
      email: email,
    )) {
      case Ok(:final value):
        draft = value;
      case Err(:final failure):
        return Err(failure);
    }

    final read = await _read();
    if (read case Err(:final failure)) return Err(failure);
    final contacts = List.of((read as Ok<List<TrustedContact>>).value);

    final index = contacts.indexWhere((contact) => contact.id == id);
    if (index == -1) return const Err(ContactNotFoundFailure());
    if (validator.hasDuplicatePhone(contacts, draft.phoneNumber, excludeId: id)) {
      return const Err(DuplicateContactFailure());
    }

    final updated = contacts[index].copyWith(
      name: draft.name,
      phoneNumber: draft.phoneNumber,
      // The form always submits the field, so an absent draft email clears a
      // previously stored one.
      email: () => draft.email,
      isEmergencyContact: isEmergencyContact,
      updatedAt: now(),
    );
    contacts[index] = updated;

    final saved = await _save(contacts);
    if (saved case Err(:final failure)) return Err(failure);
    return Ok(updated);
  }

  @override
  Future<Result<void>> deleteContact(String id) async {
    final read = await _read();
    if (read case Err(:final failure)) return Err(failure);
    final contacts = List.of((read as Ok<List<TrustedContact>>).value);

    final index = contacts.indexWhere((contact) => contact.id == id);
    if (index == -1) return const Err(ContactNotFoundFailure());
    contacts.removeAt(index);

    final saved = await _save(validator.renormalizePriorities(contacts));
    if (saved case Err(:final failure)) return Err(failure);
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<TrustedContact>>> reorderContacts(
    List<String> orderedIds,
  ) async {
    final read = await _read();
    if (read case Err(:final failure)) return Err(failure);
    final contacts = List.of((read as Ok<List<TrustedContact>>).value);

    if (orderedIds.length != contacts.length) {
      return const Err(ContactNotFoundFailure());
    }
    final byId = {for (final contact in contacts) contact.id: contact};
    final reordered = <TrustedContact>[];
    final seen = <String>{};
    for (final id in orderedIds) {
      final contact = byId[id];
      if (contact == null || !seen.add(id)) {
        return const Err(ContactNotFoundFailure());
      }
      reordered.add(contact);
    }

    final saved = await _save(validator.renormalizePriorities(reordered));
    if (saved case Err(:final failure)) return Err(failure);
    return Ok(reordered);
  }

  Future<Result<List<TrustedContact>>> _read() async {
    final String? raw;
    try {
      raw = await storage.read(ContactsStorageKeys.contacts);
    } on Exception {
      return const Err(ContactStorageFailure());
    }
    if (raw == null) return const Ok([]);

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const Err(CorruptedContactDataFailure());
    } on Exception {
      return const Err(ContactStorageFailure());
    }

    if (decoded is! Map<String, dynamic>) {
      return const Err(CorruptedContactDataFailure());
    }
    if (decoded['version'] != _contactsDocumentVersion) {
      return const Err(
        CorruptedContactDataFailure(
          message: 'Stored contact data uses an unsupported version.',
        ),
      );
    }
    final list = decoded['contacts'];
    if (list is! List) {
      return const Err(CorruptedContactDataFailure());
    }

    final contacts = <TrustedContact>[];
    for (final entry in list) {
      if (entry is! Map) return const Err(CorruptedContactDataFailure());
      final contact = _decodeContact(Map<String, dynamic>.from(entry));
      if (contact == null) return const Err(CorruptedContactDataFailure());
      contacts.add(contact);
    }

    if (!_isValidCollection(contacts)) {
      return const Err(CorruptedContactDataFailure());
    }
    return Ok(contacts);
  }

  Future<Result<List<TrustedContact>>> _save(
    List<TrustedContact> contacts,
  ) async {
    try {
      final encoded = jsonEncode({
        'version': _contactsDocumentVersion,
        'contacts': [
          for (final contact in contacts)
            {
              'id': contact.id,
              'name': contact.name,
              'phoneNumber': contact.phoneNumber,
              // Optional since Phase 3G; written as null when absent so the
              // document shape stays stable.
              'email': contact.email,
              'priority': contact.priority,
              'isEmergencyContact': contact.isEmergencyContact,
              'createdAt': contact.createdAt.toIso8601String(),
              'updatedAt': contact.updatedAt.toIso8601String(),
            },
        ],
      });
      await storage.write(ContactsStorageKeys.contacts, encoded);
      return Ok(contacts);
    } on Exception {
      return const Err(ContactStorageFailure());
    }
  }

  TrustedContact? _decodeContact(Map<String, dynamic> map) {
    final id = map['id'];
    final name = map['name'];
    final phone = map['phoneNumber'];
    final priority = map['priority'];
    final createdAt = map['createdAt'];
    final updatedAt = map['updatedAt'];

    if (id is! String || id.isEmpty) return null;
    if (name is! String || name != name.trim()) return null;
    if (name.isEmpty || name.length > TrustedContactValidator.maxNameLength) {
      return null;
    }
    if (phone is! String ||
        !PhoneNumber.isValid(phone) ||
        PhoneNumber.normalize(phone) != phone) {
      return null;
    }
    // Optional field: absent or null means "no email"; anything present must
    // be a valid normalized address (strict, like every other field).
    final rawEmail = map['email'];
    String? email;
    if (rawEmail != null) {
      if (rawEmail is! String) return null;
      email = TrustedContact.normalizeEmail(rawEmail);
      if (email != null &&
          (email.length > TrustedContactValidator.maxEmailLength ||
              !TrustedContactValidator.isValidEmail(email))) {
        return null;
      }
    }
    if (priority is! int || priority < 1) return null;

    // Optional: defaults to true for backward compatibility
    final rawIsEmergency = map['isEmergencyContact'];
    bool isEmergencyContact = true;
    if (rawIsEmergency != null) {
      if (rawIsEmergency is! bool) return null;
      isEmergencyContact = rawIsEmergency;
    }

    final created = _tryParseTimestamp(createdAt);
    if (created == null) return null;
    final updated = _tryParseTimestamp(updatedAt);
    if (updated == null || updated.isBefore(created)) return null;

    return TrustedContact(
      id: id,
      name: name,
      phoneNumber: phone,
      email: email,
      priority: priority,
      isEmergencyContact: isEmergencyContact,
      createdAt: created,
      updatedAt: updated,
    );
  }

  bool _isValidCollection(List<TrustedContact> contacts) {
    final ids = <String>{};
    final phones = <String>{};
    for (final contact in contacts) {
      if (!ids.add(contact.id)) return false;
      if (!phones.add(contact.phoneNumber)) return false;
    }
    return validator.hasValidPrioritySequence(contacts);
  }

  DateTime? _tryParseTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
