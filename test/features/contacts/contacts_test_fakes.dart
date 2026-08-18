import 'package:guardianher/features/contacts/application/contacts_controller.dart';
import 'package:guardianher/features/contacts/application/contacts_state.dart';
import 'package:guardianher/features/contacts/domain/contact_failures.dart';

import '../../helpers/fakes.dart';

/// Secure storage whose reads/writes can be forced to fail.
///
/// Extends the shared in-memory fake so most tests use the real success path.
class FlakySecureStorage extends FakeSecureStorageService {
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw Exception('read failed');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw Exception('write failed');
    return super.write(key, value);
  }
}

/// A controller that reports a permanent loading state (widget loading test).
class LoadingContactsController extends ContactsController {
  @override
  ContactsState build() => const ContactsLoading();
}

/// A controller that reports an error state (widget error test).
class ErrorContactsController extends ContactsController {
  @override
  ContactsState build() => const ContactsError(ContactStorageFailure());
}