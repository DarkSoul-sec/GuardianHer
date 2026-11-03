import '../result/result.dart';

/// Abstraction over the system share sheet (Phase 3G).
///
/// The last-resort channel of the communication cascade: when no SMS or email
/// app can handle a message, the plain text is handed to the system share
/// sheet so the user can deliver it through any installed app. Always
/// user-confirmed — nothing leaves the device without an explicit user action.
abstract interface class ShareService {
  /// Opens the system share sheet with [text] pre-filled.
  Future<Result<void>> shareText(String text);

  /// Opens the system share sheet with the local file at [filePath].
  ///
  /// The user chooses the destination; nothing is sent automatically.
  Future<Result<void>> shareFile(String filePath);
}
