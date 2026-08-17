import '../result/result.dart';

/// Abstraction over SMS intents.
///
/// Android does not permit arbitrary apps to silently send SMS (the
/// default-SMS-app restriction), so the implementation composes a message in
/// the system SMS app for the user to review and send.
abstract interface class SmsService {
  /// Opens the system SMS app with the recipient and optional [body] filled in.
  Future<Result<void>> openComposer({
    required String phoneNumber,
    String? body,
  });
}