import '../../../core/result/result.dart';

/// Schedules check-in reminder notifications on the device.
///
/// A single reminder is scheduled for the next due time; acknowledging a
/// check-in reschedules the following one. [missedCount] is passed so the
/// reminder wording can reflect escalating urgency without ever including
/// names, numbers or locations (privacy-preserving, generic content).
abstract interface class CheckInScheduler {
  /// Schedules a reminder for [dueAt]. An already-past [dueAt] fires as soon
  /// as the platform allows (used for the immediate re-notify after a miss).
  Future<Result<void>> scheduleReminder(
    DateTime dueAt, {
    required int missedCount,
  });

  /// Schedules a check-in EXECUTION for [dueAt].
  ///
  /// Unlike [scheduleReminder], the fired notification carries an execution
  /// payload: when the platform can wake Dart in the background the pipeline
  /// runs headlessly (location attempt → honest status recording → actionable
  /// notification); when it cannot, the same notification is still posted and
  /// tapping it opens the app so the pipeline completes in the foreground.
  /// Both paths are user-mediated for delivery; nothing auto-sends.
  Future<Result<void>> scheduleExecution(DateTime dueAt);

  /// Cancels any pending check-in reminders or executions. Idempotent.
  Future<Result<void>> cancelAll();
}