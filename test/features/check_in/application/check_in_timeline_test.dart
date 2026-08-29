import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/check_in/application/check_in_timeline.dart';
import 'package:guardianher/features/check_in/domain/check_in_interval.dart';

void main() {
  final ack = DateTime.utc(2026, 1, 1, 12);

  group('computeMissedCheckIns', () {
    test('returns 0 before the first interval completes', () {
      expect(
        computeMissedCheckIns(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          now: ack.add(const Duration(minutes: 30)),
        ),
        0,
      );
    });

    test('returns 0 while the current interval is still open (respond now)',
        () {
      expect(
        computeMissedCheckIns(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          now: ack.add(const Duration(minutes: 90)),
        ),
        0,
      );
    });

    test('returns 1 once a full interval passed without acknowledgment', () {
      expect(
        computeMissedCheckIns(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          now: ack.add(const Duration(minutes: 120)),
        ),
        1,
      );
    });

    test('returns 2 after two skipped intervals', () {
      expect(
        computeMissedCheckIns(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          now: ack.add(const Duration(minutes: 180)),
        ),
        2,
      );
    });

    test('never returns a negative count when ack is in the future', () {
      expect(
        computeMissedCheckIns(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          now: ack.subtract(const Duration(minutes: 10)),
        ),
        0,
      );
    });
  });

  group('computeNextDueAt', () {
    test('is one interval after the acknowledgment with no misses', () {
      expect(
        computeNextDueAt(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          missedCount: 0,
        ),
        ack.add(const Duration(minutes: 60)),
      );
    });

    test('accounts for missed intervals', () {
      expect(
        computeNextDueAt(
          lastAcknowledgedAt: ack,
          interval: CheckInInterval.minutes60,
          missedCount: 2,
        ),
        ack.add(const Duration(minutes: 180)),
      );
    });
  });
}