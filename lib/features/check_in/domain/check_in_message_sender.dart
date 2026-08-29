import '../../../core/result/result.dart';
import 'check_in_message.dart';

/// Communication abstraction for check-in delivery (Phase 3D).
///
/// Phase 3D wires this to a user-confirmed sender (the system SMS composer);
/// real automatic delivery (SMS/WhatsApp) lands in Phase 3G. Whatever the
/// implementation, it reports "message handed to the user / opened for
/// sending" — never "sent" — because V1 never sends anything silently.
abstract interface class CheckInMessageSender {
  /// Hands [message] to the user for sending. Returns the outcome of opening
  /// the sender, not a delivery confirmation.
  Future<Result<void>> send(CheckInMessage message);
}