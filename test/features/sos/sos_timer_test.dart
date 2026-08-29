import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/sos/application/sos_timer.dart';

void main() {
  group('TimerSosTimer', () {
    test('emits the initial tick synchronously', () {
      fakeAsync((async) {
        final timer = TimerSosTimer();
        final ticks = <int>[];
        timer.start(
          duration: const Duration(seconds: 3),
          onTick: ticks.add,
          onComplete: () {},
        );
        expect(ticks, [3]);
        expect(timer.isRunning, isTrue);
      });
    });

    test('ticks each second and completes exactly once at zero', () {
      fakeAsync((async) {
        final timer = TimerSosTimer();
        final ticks = <int>[];
        var completed = 0;
        timer.start(
          duration: const Duration(seconds: 3),
          onTick: ticks.add,
          onComplete: () => completed++,
        );

        async.elapse(const Duration(seconds: 1));
        expect(ticks, [3, 2]);
        expect(completed, 0);

        async.elapse(const Duration(seconds: 1));
        expect(ticks, [3, 2, 1]);
        expect(completed, 0);

        async.elapse(const Duration(seconds: 1));
        expect(ticks, [3, 2, 1]);
        expect(completed, 1);
        expect(timer.isRunning, isFalse);
      });
    });

    test('stops and drops callbacks', () {
      fakeAsync((async) {
        final timer = TimerSosTimer();
        var completed = 0;
        timer.start(
          duration: const Duration(seconds: 3),
          onTick: (_) {},
          onComplete: () => completed++,
        );
        timer.stop();
        expect(timer.isRunning, isFalse);

        async.elapse(const Duration(seconds: 10));
        expect(completed, 0);
      });
    });

    test('restarting stops the previous countdown', () {
      fakeAsync((async) {
        final timer = TimerSosTimer();
        final ticks = <int>[];
        var firstCompleted = 0;
        timer.start(
          duration: const Duration(seconds: 3),
          onTick: ticks.add,
          onComplete: () => firstCompleted++,
        );
        async.elapse(const Duration(seconds: 1));
        expect(ticks, [3, 2]);

        timer.start(
          duration: const Duration(seconds: 2),
          onTick: ticks.add,
          onComplete: () {},
        );
        expect(ticks, [3, 2, 2]);
        async.elapse(const Duration(seconds: 2));
        expect(firstCompleted, 0);
        expect(timer.isRunning, isFalse);
      });
    });

    test('zero duration completes immediately without ticking', () {
      fakeAsync((async) {
        final timer = TimerSosTimer();
        var ticks = 0;
        var completed = 0;
        timer.start(
          duration: Duration.zero,
          onTick: (_) => ticks++,
          onComplete: () => completed++,
        );
        expect(ticks, 0);
        expect(completed, 1);
        expect(timer.isRunning, isFalse);
      });
    });
  });
}
