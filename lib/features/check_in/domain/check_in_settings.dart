import 'check_in_delivery_status.dart';
import 'check_in_interval.dart';

/// Persisted Safety Check-In configuration and check-in timeline.
///
/// [recipientContactIds] reference trusted-contact ids owned by the contacts
/// feature; the display layer resolves them to names/numbers. The timeline
/// fields ([lastAcknowledgedAt], [missedCount]) survive restarts so missed
/// check-ins escalate correctly even when the app was closed.
///
/// The execution timeline ([lastAttemptAt], [lastSuccessfulLocationAt],
/// [lastExecutionStatus], [nextScheduledAt]) records what each scheduled run
/// actually did, so the UI can distinguish "location captured" from "waiting
/// for you to send" — and never claim an unattended delivery happened.
///
/// All values are app-local and non-sensitive (no phone numbers, no
/// coordinates and no location URLs are stored here), so this is persisted
/// through [PreferencesService].
class CheckInSettings {
  const CheckInSettings({
    required this.enabled,
    required this.interval,
    required this.recipientContactIds,
    this.graceMinutes = 10,
    this.lastAcknowledgedAt,
    this.missedCount = 0,
    this.lastAttemptAt,
    this.lastSuccessfulLocationAt,
    this.lastExecutionStatus,
    this.nextScheduledAt,
  });

  /// Default, disabled configuration. No reminder is scheduled until the user
  /// opts in and picks at least one recipient.
  static const CheckInSettings initial = CheckInSettings(
    enabled: false,
    interval: CheckInInterval.minutes60,
    recipientContactIds: [],
    graceMinutes: 10,
  );

  final bool enabled;
  final CheckInInterval interval;

  /// Ids of trusted contacts who receive the check-in message. May be empty
  /// while disabled; enabling requires at least one.
  final List<String> recipientContactIds;

  /// How long after a due check-in the user may still respond before it is
  /// counted as missed.
  final int graceMinutes;

  /// UTC instant of the last acknowledged check-in, or `null` before the first
  /// one. The next due time is derived from this.
  final DateTime? lastAcknowledgedAt;

  /// Number of consecutive check-ins that passed without acknowledgment.
  final int missedCount;

  /// UTC instant of the most recent scheduled execution attempt, whether it
  /// succeeded or failed. Display only.
  final DateTime? lastAttemptAt;

  /// UTC instant of the last execution that captured a FRESH fix. A stale
  /// fallback never updates this field.
  final DateTime? lastSuccessfulLocationAt;

  /// Outcome label of the last scheduled execution.
  final CheckInExecutionStatus? lastExecutionStatus;

  /// UTC instant the next execution is scheduled for, kept in sync with the
  /// platform scheduler so the UI shows what the device will actually do.
  final DateTime? nextScheduledAt;

  bool get hasRecipients => recipientContactIds.isNotEmpty;

  CheckInSettings copyWith({
    bool? enabled,
    CheckInInterval? interval,
    List<String>? recipientContactIds,
    int? graceMinutes,
    DateTime? Function()? lastAcknowledgedAt,
    int? missedCount,
    DateTime? Function()? lastAttemptAt,
    DateTime? Function()? lastSuccessfulLocationAt,
    CheckInExecutionStatus? Function()? lastExecutionStatus,
    DateTime? Function()? nextScheduledAt,
  }) {
    return CheckInSettings(
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
      recipientContactIds:
          recipientContactIds ?? this.recipientContactIds,
      graceMinutes: graceMinutes ?? this.graceMinutes,
      lastAcknowledgedAt:
          lastAcknowledgedAt != null ? lastAcknowledgedAt() : this.lastAcknowledgedAt,
      missedCount: missedCount ?? this.missedCount,
      lastAttemptAt: lastAttemptAt != null ? lastAttemptAt() : this.lastAttemptAt,
      lastSuccessfulLocationAt: lastSuccessfulLocationAt != null
          ? lastSuccessfulLocationAt()
          : this.lastSuccessfulLocationAt,
      lastExecutionStatus: lastExecutionStatus != null
          ? lastExecutionStatus()
          : this.lastExecutionStatus,
      nextScheduledAt:
          nextScheduledAt != null ? nextScheduledAt() : this.nextScheduledAt,
    );
  }
}