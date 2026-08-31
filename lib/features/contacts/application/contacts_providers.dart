import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/contacts_repository.dart';
import '../../../core/providers.dart';
import '../data/contacts_repository_impl.dart';
import 'contacts_controller.dart';
import 'contacts_state.dart';

/// Re-export [ContactsRepository] for consumers of this provider.
export '../domain/contacts_repository.dart';

/// Binds the trusted-contacts repository to secure storage.
final contactsRepositoryProvider = Provider<ContactsRepository>(
  (ref) => SecureStorageContactsRepository(
    storage: ref.watch(secureStorageServiceProvider),
  ),
);

/// The trusted-contacts controller.
final contactsControllerProvider =
    NotifierProvider<ContactsController, ContactsState>(ContactsController.new);