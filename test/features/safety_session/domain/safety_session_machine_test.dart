import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/safety_session/domain/safety_session.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_failures.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_id.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_machine.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_status.dart';
import 'package:guardianher/features/safety_session/domain/safety_session_type.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 24, 9);
  final t1 = t0.add(const Duration(seconds: 5));

  SafetySession started({
    SafetySessionType type = SafetySessionType.safeJourney,
    List<String> recipients = const [],
  }) =>
      (SafetySessionMachine.start(
        null,
        type: type,
        id: SafetySessionId.generate(),
        now: t0,
        recipientContactIds: recipients,
      ) as Ok<SafetySession>).value;

  group('SafetySessionMachine.start', () {
    test('creates a starting session from nothing', () {
      final result = SafetySessionMachine.start(
        null,
        type: SafetySessionType.sos,
        id: SafetySessionId.generate(),
        now: t0,
        recipientContactIds: ['contact-1'],
      );

      final session = result.fold((s) => s, (_) => throw StateError('err'));
      expect(session.status, SafetySessionStatus.starting);
      expect(session.type, SafetySessionType.sos);
      expect(session.startedAt, t0);
      expect(session.activatedAt, isNull);
      expect(session.endedAt, isNull);
      expect(session.recipientContactIds, ['contact-1']);
    });

    test('allows restart from every terminal state', () {
      for (final terminal in [
        started().copyWith(status: SafetySessionStatus.completed, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.expired, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.failed, endedAt: t1),
      ]) {
        final result = SafetySessionMachine.start(
          terminal,
          type: SafetySessionType.sos,
          id: SafetySessionId.generate(),
          now: t1,
        );
        expect(result.isOk, isTrue, reason: '${terminal.status} must restart');
      }
    });

    test('rejects duplicate starts while starting/active/stopping', () {
      for (final busy in [
        started(),
        started().copyWith(status: SafetySessionStatus.active, activatedAt: t1),
        started().copyWith(status: SafetySessionStatus.stopping),
      ]) {
        final result = SafetySessionMachine.start(
          busy,
          type: SafetySessionType.sos,
          id: SafetySessionId.generate(),
          now: t1,
        );

        Object? failure;
        result.fold((_) {}, (f) => failure = f);
        expect(failure, isA<DuplicateActiveSessionFailure>());
        expect((failure as DuplicateActiveSessionFailure).runningType,
            busy.type.storageName);
      }
    });
  });

  group('SafetySessionMachine.activate', () {
    test('starting → active records activation time', () {
      final result =
          SafetySessionMachine.activate(started(), now: t1);

      final session = result.fold((s) => s, (_) => throw StateError('err'));
      expect(session.status, SafetySessionStatus.active);
      expect(session.activatedAt, t1);
      expect(session.startedAt, t0); // untouched
    });

    test('rejected from every non-starting state', () {
      for (final other in [
        started().copyWith(status: SafetySessionStatus.active, activatedAt: t1),
        started().copyWith(status: SafetySessionStatus.stopping),
        started().copyWith(status: SafetySessionStatus.completed, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.failed, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.expired, endedAt: t1),
      ]) {
        final result = SafetySessionMachine.activate(other, now: t1);
        Object? failure;
        result.fold((_) {}, (f) => failure = f);
        expect(failure, isA<InvalidSafetyTransitionFailure>(),
            reason: 'activate must reject ${other.status}');
        expect(
          (failure as InvalidSafetyTransitionFailure).requestedStatus,
          'active',
        );
      }
    });
  });

  group('SafetySessionMachine.stop / complete', () {
    test('active → stopping → completed with end time', () {
      final active =
          SafetySessionMachine.activate(started(), now: t1)
              .fold((s) => s, (_) => throw StateError('err'));
      final t2 = t1.add(const Duration(seconds: 3));

      final stopping = SafetySessionMachine.stop(active, now: t2)
          .fold((s) => s, (_) => throw StateError('err'));
      expect(stopping.status, SafetySessionStatus.stopping);
      expect(stopping.endedAt, isNull); // not ended until completed

      final t3 = t2.add(const Duration(seconds: 2));
      final completed = SafetySessionMachine.complete(stopping, now: t3)
          .fold((s) => s, (_) => throw StateError('err'));
      expect(completed.status, SafetySessionStatus.completed);
      expect(completed.endedAt, t3);
      expect(completed.isTerminal, isTrue);
    });

    test('stop rejected unless active; complete rejected unless stopping',
        () {
      for (final notActive in [
        started(),
        started().copyWith(status: SafetySessionStatus.stopping),
        started().copyWith(status: SafetySessionStatus.expired, endedAt: t1),
      ]) {
        Object? failure;
        SafetySessionMachine
            .stop(notActive, now: t1)
            .fold((_) {}, (f) => failure = f);
        expect(failure, isA<InvalidSafetyTransitionFailure>());

        failure = null;
        SafetySessionMachine
            .complete(notActive.copyWith(status: SafetySessionStatus.active),
                now: t1)
            .fold((_) {}, (f) => failure = f);
        expect(failure, isA<InvalidSafetyTransitionFailure>());
      }
    });
  });

  group('SafetySessionMachine.expire', () {
    test('expires from active and from starting, recording the end time', () {
      for (final due in [started(), started().copyWith(status: SafetySessionStatus.active, activatedAt: t1)]) {
        final result = SafetySessionMachine.expire(due, now: t1);
        final session = result.fold((s) => s, (_) => throw StateError('err'));
        expect(session.status, SafetySessionStatus.expired);
        expect(session.endedAt, t1);
      }
    });

    test('rejected once already ending or terminal', () {
      for (final late in [
        started().copyWith(status: SafetySessionStatus.stopping),
        started().copyWith(status: SafetySessionStatus.completed, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.expired, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.failed, endedAt: t1),
      ]) {
        Object? failure;
        SafetySessionMachine.expire(late, now: t1).fold((_) {}, (f) => failure = f);
        expect(failure, isA<InvalidSafetyTransitionFailure>(),
            reason: 'expire must reject ${late.status}');
      }
    });
  });

  group('SafetySessionMachine.fail', () {
    test('allowed from starting/active/stopping only', () {
      for (final ok in [
        started(),
        started().copyWith(status: SafetySessionStatus.active, activatedAt: t1),
        started().copyWith(status: SafetySessionStatus.stopping),
      ]) {
        final result = SafetySessionMachine.fail(ok, now: t1);
        final session = result.fold((s) => s, (_) => throw StateError('err'));
        expect(session.status, SafetySessionStatus.failed);
        expect(session.endedAt, t1);
      }

      for (final no in [
        started().copyWith(status: SafetySessionStatus.completed, endedAt: t1),
        started().copyWith(status: SafetySessionStatus.expired, endedAt: t1),
      ]) {
        Object? failure;
        SafetySessionMachine.fail(no, now: t1).fold((_) {}, (f) => failure = f);
        expect(failure, isA<InvalidSafetyTransitionFailure>());
      }
    });
  });

  group('SafetySession value semantics', () {
    test('copyWith keeps identity and immutability guarantees', () {
      final original = started(recipients: const ['a']);
      final copy = original.copyWith(status: SafetySessionStatus.active);

      expect(copy.id, original.id);
      expect(copy.recipientContactIds, ['a']);
      // Mutating the copy's list never reaches back into the original.
      final mutated =
          original.copyWith(recipientContactIds: ['x']).recipientContactIds;
      mutated.add('y');
      expect(original.recipientContactIds, ['a']);
    });

    test('toString stays free of recipients and PII', () {
      final session =
          started(recipients: const ['secret-contact-id-1234567890']);
      final text = session.toString();
      expect(text, contains('safe_journey'));
      expect(text, isNot(contains('secret-contact-id')));
    });
  });
}
