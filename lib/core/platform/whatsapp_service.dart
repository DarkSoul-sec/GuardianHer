import '../result/result.dart';

/// Abstraction over opening a pre-filled WhatsApp chat.
///
/// Like the SMS and email services, this only ever OPENS an app for the user
/// to review and send: nothing is transmitted automatically. The service
/// cannot know whether the recipient is registered on WhatsApp — if the number
/// is unknown to WhatsApp, WhatsApp itself reports that after opening. The
/// failure result therefore means "the chat could not be opened", never "not
/// delivered".
abstract interface class WhatsAppService {
  /// Opens a WhatsApp chat with [phoneNumber], optionally pre-filled with
  /// [body].
  ///
  /// [phoneNumber] may be in any human format; it is canonicalized into the
  /// digits-only international form the `wa.me` deep link requires before the
  /// link is built.
  Future<Result<void>> openChat({
    required String phoneNumber,
    String? body,
  });
}
