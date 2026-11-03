import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/fake_call/application/fake_call_providers.dart';
import 'package:guardianher/features/fake_call/domain/fake_call_config.dart';
import 'package:guardianher/features/fake_call/domain/fake_call_state.dart';

import '../../helpers/fakes.dart';

class _Harness {
  _Harness() {
    alert = FakeFakeCallAlert();
    notifier = FakeFakeCallNotifier();
    container = createContainer(
      overrides: [
        fakeCallAlertServiceProvider.overrideWithValue(alert),
        fakeCallNotifierProvider.overrideWithValue(notifier),
      ],
    );
  }

  late final FakeFakeCallAlert alert;
  late final FakeFakeCallNotifier notifier;
  late final ProviderContainer container;

  FakeCallState get state => container.read(fakeCallControllerProvider);

  void dispose() => container.dispose();
}

void main() {
  group('FakeCallConfig defaults', () {
    test('default caller is Mom with 10s delay and vibration on', () {
      const config = FakeCallConfig();
      expect(config.callerName, 'Mom');
      expect(config.callerNumber, 'Incoming Call');
      expect(config.delay, FakeCallDelay.seconds10);
      expect(config.vibrationEnabled, isTrue);
    });

    test('delay set contains exactly 5s/10s/30s/1m', () {
      expect(
        FakeCallDelay.values.map((d) => d.duration).toList(),
        [
          const Duration(seconds: 5),
          const Duration(seconds: 10),
          const Duration(seconds: 30),
          const Duration(minutes: 1),
        ],
      );
    });
  });

  group('FakeCallController', () {
    test('starts idle', () {
      final h = _Harness();
      addTearDown(h.dispose);
      expect(h.state, const FakeCallIdle());
    });

    test('schedule moves idle to scheduled and scripts the notifier', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.container
          .read(fakeCallControllerProvider.notifier)
          .scheduleFakeCall(const FakeCallConfig());

      final state = h.state;
      expect(state, isA<FakeCallScheduled>());
      expect(
        (state as FakeCallScheduled).config.callerName,
        'Mom',
      );
      expect(h.notifier.scheduleCalls, 1);
      expect(h.notifier.lastCallerName, 'Mom');
    });

    test('scheduled fires into ringing and starts the alert', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        h.container
            .read(fakeCallControllerProvider.notifier)
            .scheduleFakeCall(const FakeCallConfig());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        expect(h.state, isA<FakeCallRinging>());
        expect(h.alert.startCalls, 1);
        expect(h.alert.lastVibrate, isTrue);
        expect(h.notifier.showCalls, 1);
      });
    });

    test('ringing answers into active with a ticking timer', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        final notifier = h.container.read(fakeCallControllerProvider.notifier);
        notifier.scheduleFakeCall(const FakeCallConfig());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        notifier.answerCall();
        async.flushMicrotasks();
        expect(h.state, isA<FakeCallActive>());
        expect((h.state as FakeCallActive).elapsed, Duration.zero);
        expect(h.alert.stopCalls, 1);
        expect(h.notifier.cancelCalls, greaterThanOrEqualTo(1));

        async.elapse(const Duration(seconds: 3));
        expect((h.state as FakeCallActive).elapsed, const Duration(seconds: 3));
      });
    });

    test('ringing declines into ended and silences the alert', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        final notifier = h.container.read(fakeCallControllerProvider.notifier);
        notifier.scheduleFakeCall(const FakeCallConfig());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        notifier.declineCall();
        async.flushMicrotasks();

        final state = h.state;
        expect(state, isA<FakeCallEnded>());
        expect(
          (state as FakeCallEnded).reason,
          FakeCallEndReason.declined,
        );
        expect(h.alert.stopCalls, 1);
        expect(h.notifier.cancelCalls, greaterThanOrEqualTo(1));
      });
    });

    test('active ends into hung-up and stops the ticker', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        final notifier = h.container.read(fakeCallControllerProvider.notifier);
        notifier.scheduleFakeCall(const FakeCallConfig());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        notifier.answerCall();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));

        notifier.endCall();
        async.flushMicrotasks();

        expect(h.state, isA<FakeCallEnded>());
        expect(
          (h.state as FakeCallEnded).reason,
          FakeCallEndReason.hungUp,
        );
        async.elapse(const Duration(seconds: 30));
        expect(h.state, isA<FakeCallEnded>());
      });
    });

    test('unanswered ringing times out after 30s', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        h.container
            .read(fakeCallControllerProvider.notifier)
            .scheduleFakeCall(const FakeCallConfig());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(h.state, isA<FakeCallRinging>());

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(h.state, isA<FakeCallEnded>());
        expect(
          (h.state as FakeCallEnded).reason,
          FakeCallEndReason.timedOut,
        );
        expect(h.alert.stopCalls, 1);
      });
    });

    test('duplicate schedule while busy is absorbed', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final notifier = h.container.read(fakeCallControllerProvider.notifier);
      await notifier.scheduleFakeCall(const FakeCallConfig());
      await notifier.scheduleFakeCall(
        const FakeCallConfig(callerName: 'Dad'),
      );

      final state = h.state;
      expect(state, isA<FakeCallScheduled>());
      expect(
        (state as FakeCallScheduled).config.callerName,
        'Mom',
      );
      expect(h.notifier.scheduleCalls, 1);
    });

    test('cancel removes a scheduled call', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final notifier = h.container.read(fakeCallControllerProvider.notifier);
      await notifier.scheduleFakeCall(const FakeCallConfig());
      await notifier.cancelFakeCall();

      final state = h.state;
      expect(state, isA<FakeCallEnded>());
      expect(
        (state as FakeCallEnded).reason,
        FakeCallEndReason.cancelled,
      );
      h.container.dispose();
    });

    test('answer/decline/end are no-ops outside their states', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final notifier = h.container.read(fakeCallControllerProvider.notifier);
      await notifier.answerCall();
      await notifier.declineCall();
      await notifier.endCall();
      expect(h.state, const FakeCallIdle());
      expect(h.alert.startCalls, 0);
      expect(h.alert.stopCalls, 0);
    });

    test('vibration flag reaches the alert seam', () {
      fakeAsync((async) {
        final h = _Harness();
        addTearDown(h.dispose);
        h.container.read(fakeCallControllerProvider.notifier).scheduleFakeCall(
              const FakeCallConfig(vibrationEnabled: false),
            );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(h.alert.lastVibrate, isFalse);
      });
    });
  });
}
