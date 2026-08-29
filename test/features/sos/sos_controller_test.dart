import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/sos/application/sos_controller.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';
import 'package:guardianher/features/sos/domain/sos_status.dart';

import 'sos_test_fakes.dart';

void main() {
  group('SosController', () {
    test('starts in the idle state', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);

      expect(
        fixture.container.read(sosControllerProvider),
        isA<SosIdle>(),
      );
    });

    test('startSos arms a countdown with the configured duration', () {
      final fixture = createSosContainer(countdownDuration: const Duration(seconds: 5));
      addTearDown(fixture.container.dispose);

      fixture.container.read(sosControllerProvider.notifier).startSos();

      final state = fixture.container.read(sosControllerProvider);
      expect(state, isA<SosCountdown>());
      final countdown = state as SosCountdown;
      expect(countdown.remainingSeconds, 5);
      expect(countdown.event.id.value, testSosEventId);
      expect(countdown.event.status, SosStatus.countdown);
      expect(countdown.event.startedAt, DateTime(2026, 1, 1, 12));
      expect(fixture.timer.startedDuration, const Duration(seconds: 5));
      expect(fixture.timer.startCalls, 1);
    });

    test('a second startSos while armed is ignored', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      controller.startSos();

      expect(fixture.timer.startCalls, 1);
      expect(
        fixture.container.read(sosControllerProvider),
        isA<SosCountdown>(),
      );
    });

    test('countdown ticks then activates at zero', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      expect(
        (fixture.container.read(sosControllerProvider) as SosCountdown)
            .remainingSeconds,
        3,
      );

      fixture.timer.tick();
      expect(
        (fixture.container.read(sosControllerProvider) as SosCountdown)
            .remainingSeconds,
        2,
      );

      fixture.timer.tick();
      expect(
        (fixture.container.read(sosControllerProvider) as SosCountdown)
            .remainingSeconds,
        1,
      );

      fixture.timer.tick();
      final state = fixture.container.read(sosControllerProvider);
      expect(state, isA<SosActive>());
      final active = state as SosActive;
      expect(active.event.status, SosStatus.active);
      expect(active.event.activatedAt, DateTime(2026, 1, 1, 12));
      expect(fixture.timer.isRunning, isFalse);
    });

    test('cancelSos during countdown stops it and finalizes to completed', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      controller.cancelSos();

      var state = fixture.container.read(sosControllerProvider);
      expect(state, isA<SosCancelling>());
      expect(fixture.timer.startedDuration, SosController.cancellationDelay);
      expect(fixture.timer.isRunning, isTrue);

      fixture.timer.fireComplete();
      state = fixture.container.read(sosControllerProvider);
      expect(state, isA<SosCompleted>());
      final completed = state as SosCompleted;
      expect(completed.event.status, SosStatus.completed);
      expect(completed.event.reason, SosTerminationReason.cancelled);
      expect(completed.event.completedAt, DateTime(2026, 1, 1, 12));
    });

    test('cancelSos during active finalizes to completed (cancelled)', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      fixture.timer.tick();
      fixture.timer.tick();
      fixture.timer.tick();
      expect(fixture.container.read(sosControllerProvider), isA<SosActive>());

      controller.cancelSos();
      expect(
        fixture.container.read(sosControllerProvider),
        isA<SosCancelling>(),
      );
      fixture.timer.fireComplete();

      final completed =
          fixture.container.read(sosControllerProvider) as SosCompleted;
      expect(completed.event.reason, SosTerminationReason.cancelled);
    });

    test('cancelSos while idle is a no-op', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);

      fixture.container.read(sosControllerProvider.notifier).cancelSos();

      expect(fixture.timer.startCalls, 0);
      expect(fixture.container.read(sosControllerProvider), isA<SosIdle>());
    });

    test('completeSos finishes an active session normally', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      fixture.timer.tick();
      fixture.timer.tick();
      fixture.timer.tick();
      expect(fixture.container.read(sosControllerProvider), isA<SosActive>());

      controller.completeSos();
      final completed =
          fixture.container.read(sosControllerProvider) as SosCompleted;
      expect(completed.event.reason, SosTerminationReason.completed);
      expect(fixture.timer.isRunning, isFalse);
    });

    test('completeSos while idle is a no-op', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);

      fixture.container.read(sosControllerProvider.notifier).completeSos();

      expect(fixture.container.read(sosControllerProvider), isA<SosIdle>());
    });

    test('resetSos returns to idle after completion and allows a new session', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      fixture.timer.tick();
      fixture.timer.tick();
      fixture.timer.tick();
      controller.cancelSos();
      fixture.timer.fireComplete();
      expect(fixture.container.read(sosControllerProvider), isA<SosCompleted>());

      controller.resetSos();
      expect(fixture.container.read(sosControllerProvider), isA<SosIdle>());

      controller.startSos();
      expect(fixture.container.read(sosControllerProvider), isA<SosCountdown>());
      expect(fixture.timer.startedDuration, const Duration(seconds: 3));
    });

    test('a new session can start straight from a completed one', () {
      final fixture = createSosContainer();
      addTearDown(fixture.container.dispose);
      final controller = fixture.container.read(sosControllerProvider.notifier);

      controller.startSos();
      fixture.timer.tick();
      fixture.timer.tick();
      fixture.timer.tick();
      controller.cancelSos();
      fixture.timer.fireComplete();

      controller.startSos();
      final state = fixture.container.read(sosControllerProvider);
      expect(state, isA<SosCountdown>());
      expect((state as SosCountdown).event.id.value, testSosEventId);
      expect(fixture.timer.startedDuration, const Duration(seconds: 3));
    });
  });
}
