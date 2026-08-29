import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/domain/sos_failures.dart';
import 'package:guardianher/features/sos/domain/sos_state_machine.dart';
import 'package:guardianher/features/sos/domain/sos_status.dart';

import 'sos_test_fakes.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);
  final duration = const Duration(seconds: 3);
  final id = SosEventId(testSosEventId);

  group('SosStateMachine.start', () {
    test('arms a countdown from no current session', () {
      final result = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      );
      expect(result, isA<Ok<SosEvent>>());
      final event = result.getOrNull()!;
      expect(event.id, id);
      expect(event.status, SosStatus.countdown);
      expect(event.startedAt, now);
      expect(event.countdownDuration, duration);
      expect(event.activatedAt, isNull);
      expect(event.completedAt, isNull);
      expect(event.reason, isNull);
    });

    test('rejects a second session while one is running', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final result = SosStateMachine.start(
        started,
        id: id,
        now: now,
        countdownDuration: duration,
      );
      expect(result, isA<Err<SosEvent>>());
      expect(
        (result as Err).failure,
        isA<InvalidTransitionFailure>(),
      );
    });

    test('allows a new session after the previous one completed', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final completed = SosStateMachine.complete(
        SosStateMachine.activate(started, now: now).getOrNull()!,
        now: now,
      ).getOrNull()!;
      expect(completed.status, SosStatus.completed);

      final again = SosStateMachine.start(
        completed,
        id: SosEventId.generate(),
        now: now,
        countdownDuration: duration,
      );
      expect(again, isA<Ok<SosEvent>>());
      expect(again.getOrNull()!.status, SosStatus.countdown);
    });
  });

  group('SosStateMachine.activate', () {
    test('activates a countdown and records the time', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final activatedAt = now.add(const Duration(seconds: 3));
      final result = SosStateMachine.activate(started, now: activatedAt);
      expect(result, isA<Ok<SosEvent>>());
      final event = result.getOrNull()!;
      expect(event.status, SosStatus.active);
      expect(event.activatedAt, activatedAt);
    });

    test('rejects activation from a non-countdown state', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final active = SosStateMachine.activate(started, now: now).getOrNull()!;
      final result = SosStateMachine.activate(active, now: now);
      expect(result, isA<Err<SosEvent>>());
    });
  });

  group('SosStateMachine.cancel', () {
    test('cancels a countdown session', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final result = SosStateMachine.cancel(started, now: now);
      expect(result, isA<Ok<SosEvent>>());
      final event = result.getOrNull()!;
      expect(event.status, SosStatus.cancelling);
      expect(event.reason, SosTerminationReason.cancelled);
    });

    test('cancels an active session', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final active = SosStateMachine.activate(started, now: now).getOrNull()!;
      final result = SosStateMachine.cancel(active, now: now);
      expect(result, isA<Ok<SosEvent>>());
      expect(result.getOrNull()!.status, SosStatus.cancelling);
    });

    test('is idempotent while cancelling', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final cancelling = SosStateMachine.cancel(started, now: now).getOrNull()!;
      final again = SosStateMachine.cancel(cancelling, now: now);
      expect(again, isA<Ok<SosEvent>>());
      expect(again.getOrNull()!.status, SosStatus.cancelling);
    });

    test('rejects cancellation from idle or completed', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final active = SosStateMachine.activate(started, now: now).getOrNull()!;
      final completed = SosStateMachine.complete(active, now: now).getOrNull()!;
      expect(
        SosStateMachine.cancel(completed, now: now),
        isA<Err<SosEvent>>(),
      );
    });
  });

  group('SosStateMachine.complete', () {
    test('completes normally from active', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final active = SosStateMachine.activate(started, now: now).getOrNull()!;
      final completedAt = now.add(const Duration(minutes: 1));
      final result = SosStateMachine.complete(active, now: completedAt);
      expect(result, isA<Ok<SosEvent>>());
      final event = result.getOrNull()!;
      expect(event.status, SosStatus.completed);
      expect(event.reason, SosTerminationReason.completed);
      expect(event.completedAt, completedAt);
    });

    test('preserves the cancelled reason from cancelling', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final cancelling = SosStateMachine.cancel(started, now: now).getOrNull()!;
      final result = SosStateMachine.complete(cancelling, now: now);
      expect(result, isA<Ok<SosEvent>>());
      final event = result.getOrNull()!;
      expect(event.status, SosStatus.completed);
      expect(event.reason, SosTerminationReason.cancelled);
      expect(event.completedAt, now);
    });

    test('is idempotent while completed', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final active = SosStateMachine.activate(started, now: now).getOrNull()!;
      final completed = SosStateMachine.complete(active, now: now).getOrNull()!;
      final again = SosStateMachine.complete(completed, now: now);
      expect(again, isA<Ok<SosEvent>>());
      expect(again.getOrNull()!.status, SosStatus.completed);
    });

    test('rejects completion from idle or countdown', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      expect(
        SosStateMachine.complete(started, now: now),
        isA<Err<SosEvent>>(),
      );
    });
  });

  group('SosStateMachine.resetToIdle', () {
    test('returns a completed session to idle', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      final active = SosStateMachine.activate(started, now: now).getOrNull()!;
      final completed = SosStateMachine.complete(active, now: now).getOrNull()!;
      final result = SosStateMachine.resetToIdle(completed);
      expect(result, isA<Ok<SosEvent>>());
      expect(result.getOrNull()!.status, SosStatus.idle);
    });

    test('rejects reset from a non-completed session', () {
      final started = SosStateMachine.start(
        null,
        id: id,
        now: now,
        countdownDuration: duration,
      ).getOrNull()!;
      expect(
        SosStateMachine.resetToIdle(started),
        isA<Err<SosEvent>>(),
      );
    });
  });

  group('SosEventId', () {
    test('parses a valid id', () {
      expect(SosEventId.tryParse(testSosEventId)?.value, testSosEventId);
    });

    test('rejects malformed ids', () {
      expect(SosEventId.tryParse(''), isNull);
      expect(SosEventId.tryParse('not-hex'), isNull);
      expect(SosEventId.tryParse('a' * 31), isNull);
      expect(SosEventId.tryParse('A' * 32), isNull);
    });

    test('generates unique ids', () {
      final a = SosEventId.generate();
      final b = SosEventId.generate();
      expect(a.value.length, 32);
      expect(a, isNot(b));
      expect(a.isValid, isTrue);
    });
  });
}
