import '../domain/check_in_interval.dart';

/// How many check-in intervals have fully elapsed since [lastAcknowledgedAt]
/// without acknowledgment.
///
/// The interval that is currently due counts as "respond now", not "missed";
/// a check-in only becomes missed once the *next* interval has begun. Concretely:
/// * 0..59 min after the last ack with a 60 min interval → 0 missed (due now);
/// * 60..119 min → 0 missed (still the same open interval, respond now);
/// * 120..179 min → 1 missed (the first interval was skipped entirely).
int computeMissedCheckIns({
  required DateTime lastAcknowledgedAt,
  required CheckInInterval interval,
  required DateTime now,
}) {
  final elapsedMinutes =
      now.difference(lastAcknowledgedAt).inMinutes.clamp(0, 1 << 31);
  final completedIntervals = elapsedMinutes ~/ interval.minutes;
  if (completedIntervals <= 0) {
    return 0;
  }
  return completedIntervals - 1;
}

/// The next scheduled due instant for a check-in stream.
///
/// Derived purely from the last acknowledgment: the (missed + 1)-th interval
/// boundary after [lastAcknowledgedAt]. Because it is deterministic, it is
/// always consistent across restarts and never requires extra bookkeeping.
DateTime computeNextDueAt({
  required DateTime lastAcknowledgedAt,
  required CheckInInterval interval,
  required int missedCount,
}) {
  return lastAcknowledgedAt.add(
    interval.duration * (missedCount + 1),
  );
}