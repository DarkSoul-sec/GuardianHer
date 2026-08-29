import 'package:url_launcher/url_launcher.dart';

import '../core/error/failures.dart';
import '../core/platform/call_service.dart';
import '../core/result/result.dart';

/// Builds the `tel:` URI that opens the system dialer for [normalizedNumber]
/// (digits only). E.164-style `+` prefix improves dialer handling.
Uri buildDialUri(String normalizedNumber) {
  return Uri(scheme: 'tel', path: '+$normalizedNumber');
}

/// Opens the system dialer pre-filled with a phone number.
///
/// Uses `ACTION_DIAL` (via `tel:`) which requires no `CALL_PHONE` permission.
/// The user is always in control: the call is placed only when they press the
/// dialer's call button. This service only ever reports "dialer opened".
class UrlLauncherCallService implements CallService {
  const UrlLauncherCallService();

  @override
  Future<Result<void>> openDialer(String phoneNumber) async {
    final uri = buildDialUri(phoneNumber);
    try {
      if (!await canLaunchUrl(uri)) {
        return Err(NoDialerAvailableFailure());
      }
      final launched = await launchUrl(uri);
      if (!launched) {
        return Err(NoDialerAvailableFailure());
      }
      return const Ok(null);
    } catch (_) {
      return Err(PlatformActionFailure('Unable to open the dialer.'));
    }
  }
}