import 'package:share_plus/share_plus.dart';

import '../core/error/failures.dart';
import '../core/platform/share_service.dart';
import '../core/result/result.dart';

/// Opens the system share sheet (Phase 3G share fallback).
///
/// The last-resort delivery channel: when no SMS or email app is available,
/// the message text is handed to whatever apps the device offers. Always
/// user-confirmed — nothing leaves the device without an explicit action.
class SharePlusShareService implements ShareService {
  const SharePlusShareService();

  @override
  Future<Result<void>> shareText(String text) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, title: 'GuardianHer'),
      );
      // Any non-throwing result means the sheet opened. On Android the chosen
      // target often cannot be determined ("unavailable"), and "dismissed"
      // still means the user was offered every installed channel — neither is
      // a delivery failure.
      return const Ok(null);
    } catch (_) {
      return const Err(ShareUnavailableFailure());
    }
  }
}
