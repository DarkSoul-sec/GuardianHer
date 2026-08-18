import '../../../core/error/failures.dart';
import '../domain/trusted_contact.dart';

/// States of the trusted-contacts feature.
///
/// `initial`/`loading` is the controller's first build; `loaded` is the
/// primary state carrying the contact list; `error` reports a load failure
/// (e.g. corrupted storage). [ContactsLoaded.saving] flags an in-flight
/// mutation so the UI can disable actions without extra state.
sealed class ContactsState {
  const ContactsState();
}

/// Initial load in progress.
final class ContactsLoading extends ContactsState {
  const ContactsLoading();
}

/// A contact collection is available.
final class ContactsLoaded extends ContactsState {
  const ContactsLoaded({required this.contacts, this.saving = false});

  final List<TrustedContact> contacts;

  /// Whether a mutation (add/update/delete/reorder) is in progress.
  final bool saving;

  ContactsLoaded copyWith({
    List<TrustedContact>? contacts,
    bool? saving,
  }) {
    return ContactsLoaded(
      contacts: contacts ?? this.contacts,
      saving: saving ?? this.saving,
    );
  }
}

/// The contact list could not be loaded.
final class ContactsError extends ContactsState {
  const ContactsError(this.failure);

  final Failure failure;
}
