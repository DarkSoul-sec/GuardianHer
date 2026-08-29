import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../domain/contacts_repository.dart';
import '../domain/trusted_contact.dart';
import 'contacts_providers.dart';
import 'contacts_state.dart';

/// Owns the trusted-contacts UI state.
///
/// All reads and mutations flow through [ContactsRepository]; widgets never
/// touch storage directly. Business rules (validation, duplicates, max count,
/// priority normalization) are enforced by the repository, which reloads the
/// canonical list into state after every successful mutation.
class ContactsController extends Notifier<ContactsState> {
  ContactsRepository get _repository => ref.read(contactsRepositoryProvider);

  @override
  ContactsState build() {
    _load();
    return const ContactsLoading();
  }

  /// Forces a fresh load from storage.
  Future<void> reload() => _load();

  /// Adds a contact at the lowest priority.
  Future<Result<TrustedContact>> addContact({
    required String name,
    required String phoneNumber,
    String? email,
    bool isEmergencyContact = true,
  }) {
    return _mutate(
      () => _repository.addContact(
        name: name,
        phoneNumber: phoneNumber,
        email: email,
        isEmergencyContact: isEmergencyContact,
      ),
    );
  }

  /// Updates an existing contact, preserving its id and creation time.
  Future<Result<TrustedContact>> updateContact({
    required String id,
    required String name,
    required String phoneNumber,
    String? email,
    bool isEmergencyContact = true,
  }) {
    return _mutate(
      () => _repository.updateContact(
        id: id,
        name: name,
        phoneNumber: phoneNumber,
        email: email,
        isEmergencyContact: isEmergencyContact,
      ),
    );
  }

  /// Deletes a contact and re-normalizes remaining priorities.
  Future<Result<void>> deleteContact(String id) {
    return _mutate(() => _repository.deleteContact(id));
  }

  /// Reorders contacts into [orderedIds] and re-assigns priorities.
  Future<Result<void>> reorderContacts(List<String> orderedIds) {
    return _mutate(() async {
      final result = await _repository.reorderContacts(orderedIds);
      return result is Ok ? const Ok<void>(null) : result;
    });
  }

  Future<Result<T>> _mutate<T>(Future<Result<T>> Function() operation) async {
    final current = state;
    if (current is ContactsLoaded) {
      state = current.copyWith(saving: true);
    }

    final result = await operation();
    switch (result) {
      case Ok():
        await _load();
      case Err():
        final after = state;
        if (after is ContactsLoaded) {
          state = after.copyWith(saving: false);
        }
    }
    return result;
  }

  Future<void> _load() async {
    final result = await _repository.loadContacts();
    state = switch (result) {
      Ok(:final value) => ContactsLoaded(contacts: value),
      Err(:final failure) => ContactsError(failure),
    };
  }
}
