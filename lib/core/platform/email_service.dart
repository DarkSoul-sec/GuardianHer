import '../result/result.dart';

/// Abstraction over email compose intents (Phase 3G).
///
/// Like the SMS strategy, email delivery is always user-confirmed: the
/// implementation opens the system email composer with recipients, subject and
/// body pre-filled (`ACTION_SENDTO mailto:`), requiring no permissions and
/// never sending anything silently. It only ever reports "composer opened" —
/// never "email sent".
abstract interface class EmailService {
  /// Opens the system email app with [addresses], [subject] and [body]
  /// filled in. [addresses] must be normalized (trimmed) addresses.
  Future<Result<void>> compose({
    required List<String> addresses,
    required String subject,
    required String body,
  });
}
