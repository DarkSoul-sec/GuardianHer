/// A prepared safety check-in message for delivery to trusted recipients.
///
/// [recipientPhoneNumbers] are normalized (digits-only, as stored) phone
/// numbers; [recipientEmails] are optional fallback addresses (normalized,
/// lower-cased) used only when no SMS app can handle the message.
/// [missedCount] reflects how many prior check-ins went unanswered so the
/// message can honestly convey escalating urgency. Nothing is ever sent
/// automatically — [CheckInMessageSender] hands it to the user to send.
class CheckInMessage {
  const CheckInMessage({
    required this.recipientPhoneNumbers,
    required this.body,
    required this.missedCount,
    required this.composedAt,
    this.recipientEmails = const [],
  });

  final List<String> recipientPhoneNumbers;

  /// Optional email fallback addresses (may be empty).
  final List<String> recipientEmails;

  /// The full message text (location link, check-in wording, urgency).
  final String body;

  final int missedCount;

  /// UTC instant the message was composed.
  final DateTime composedAt;

  bool get isUrgent => missedCount > 0;
}
