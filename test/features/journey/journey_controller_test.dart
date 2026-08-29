import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/features/journey/application/emergency_vehicle_context.dart';
import 'package:guardianher/features/journey/application/journey_providers.dart';
import 'package:guardianher/features/journey/domain/journey_state.dart';
import 'package:guardianher/features/live_location/application/live_location_providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/live_location/data/live_location_api_client.dart';
import 'package:guardianher/features/live_location/domain/live_location_session.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';

import '../../helpers/fakes.dart';
import '../sos/sos_test_fakes.dart';

/// Fixture wiring a journey container with a CONFIGURED live backend whose
/// creations hand out DISTINCT tokens, so ownership across two sessions
/// (journey → emergency) is observable.
class JourneyFixture {
  JourneyFixture() {
    api = SequencedTokensApi()..configured = true;
    final sos = createSosContainer(extraOverrides: [
      liveLocationApiClientProvider.overrideWithValue(api),
    ]);
    container = sos.container;
    timer = sos.timer;
  }

  late final SequencedTokensApi api;
  late final ProviderContainer container;
  late final FakeSosTimer timer;

  JourneyState get state => container.read(journeyControllerProvider);

  void armSos() {
    container.read(sosControllerProvider.notifier).startSos();
    timer.fireComplete();
  }
}

class SequencedTokensApi extends FakeLiveLocationApiClient {
  int _sequence = 0;

  String get lastToken => creation!.token;

  @override
  Future<Result<LiveSessionCreation>> createSession({
    required LiveShareDuration duration,
    required LiveUpdateInterval interval,
  }) {
    _sequence++;
    creation = LiveSessionCreation(
      token: 'token-$_sequence-${'t' * 36}',
      shareUrl: 'https://live.example.org/live/journey-$_sequence',
      expiresAt: DateTime.now().toUtc().add(duration.asDuration),
    );
    return super.createSession(duration: duration, interval: interval);
  }
}

void main() {
  test('start runs the journey on the normal cadence with a share link',
      () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    f.container.read(journeyControllerProvider);

    await f.container
        .read(journeyControllerProvider.notifier)
        .startJourney(
        vehicle: const VehicleInfo(
          type: VehicleType.taxi,
          registrationNumber: 'DL01AB1234',
        ),
      );

    final state = f.state;
    expect(state, isA<JourneyActive>());
    final active = state as JourneyActive;
    expect(active.shareUrl, contains('https://live.example.org'));
    expect(active.vehicle?.type, VehicleType.taxi);
    expect(active.vehicle?.displayRegistrationNumber, 'DL 01 AB 1234');
    expect(active.session.type.storageName, 'safe_journey');
    expect(f.api.createCalls, 1);
    expect(f.api.lastCreateInterval, LiveUpdateInterval.normal);
  });

  test('a duplicate start is absorbed silently', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);

    await notifier.startJourney();
    final first = f.state as JourneyActive;
    await notifier.startJourney();

    expect(f.state, same(first));
    expect(f.api.createCalls, 1,
        reason: 'exactly one live session, never two');
  });

  test('starting is refused while an emergency is engaged', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    f.container.read(journeyControllerProvider);
    f.armSos();
    expect(f.container.read(sosControllerProvider), isA<SosActive>());

    await f.container.read(journeyControllerProvider.notifier).startJourney();

    final state = f.state;
    expect(state, isA<JourneyIdle>());
    expect((state as JourneyIdle).notice, isNotNull);
    expect(f.api.createCalls, 0);
  });

  test('a vehicle attached at start rides the active session and the '
      'emergency context', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    const vehicle = VehicleInfo(
      type: VehicleType.cab,
      registrationNumber: 'dl01ab1234',
      driverName: ' Ramesh ',
      bookingReference: 'UB-771234',
    );
    await f.container
        .read(journeyControllerProvider.notifier)
        .startJourney(vehicle: vehicle);

    final active = f.state as JourneyActive;
    // Normalized on the way in; display derives the spaced form.
    expect(active.vehicle?.registrationNumber, 'DL01AB1234');
    expect(active.vehicle?.driverName, 'Ramesh');
    expect(active.vehicle?.bookingReference, 'UB-771234');
    expect(
      f.container.read(emergencyVehicleContextProvider),
      same(active.vehicle),
    );
  });

  test('SOS escalation PRESERVES the vehicle context and releases it only '
      'when the emergency ends (no re-entry required)', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    await f.container.read(journeyControllerProvider.notifier).startJourney(
          vehicle:
              const VehicleInfo(type: VehicleType.taxi, registrationNumber: 'DL01AB1234'),
        );

    f.armSos();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final completedAtEscalation = f.state as JourneyCompleted;

    // While the emergency is live the context MUST survive.
    expect(f.container.read(sosControllerProvider), isA<SosActive>());
    final context = f.container.read(emergencyVehicleContextProvider);
    expect(context?.registrationNumber, 'DL01AB1234');
    expect((f.state as JourneyCompleted).vehicle?.registrationNumber,
        'DL01AB1234');

    // End the SOS: terminal state releases the context automatically.
    f.container.read(sosControllerProvider.notifier).cancelSos();
    f.timer.fireComplete();
    await Future<void>.delayed(Duration.zero);
    expect(f.container.read(sosControllerProvider), isA<SosCompleted>());
    expect(f.container.read(emergencyVehicleContextProvider), isNull);
    expect(completedAtEscalation.startedAt.isBefore(DateTime(2027)), isTrue);
  });

  test('starting a NEW journey never inherits the previous vehicle',
      () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney(
      vehicle: const VehicleInfo(
        type: VehicleType.bus,
        registrationNumber: 'KA05MK4532',
      ),
    );

    await notifier.endJourney();
    notifier.dismissCompletion();
    expect(f.container.read(emergencyVehicleContextProvider), isNull);

    // Next journey starts WITHOUT a vehicle: context stays empty.
    await notifier.startJourney();
    expect(f.state, isA<JourneyActive>());
    expect((f.state as JourneyActive).vehicle, isNull);
    expect(f.container.read(emergencyVehicleContextProvider), isNull);

    // And with one: it REPLACES, never merges.
    await notifier.endJourney();
    notifier.dismissCompletion();
    await notifier.startJourney(
      vehicle: const VehicleInfo(type: VehicleType.auto),
    );
    final replaced =
        f.container.read(emergencyVehicleContextProvider);
    expect(replaced?.type, VehicleType.auto);
    expect(replaced?.registrationNumber, isNull);
    await notifier.endJourney();
  });

  test('a shake during a journey TRANSFORMS it: the journey share is torn '
      'down and exactly ONE emergency share replaces it', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney();
    final journeyToken = f.api.lastToken;

    // Shake SOS arms and activates (fake timer fires instantly).
    f.armSos();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(f.container.read(sosControllerProvider), isA<SosActive>());
    final state = f.state;
    expect(state, isA<JourneyCompleted>());
    expect(
      (state as JourneyCompleted).reason,
      JourneyEndReason.escalatedToSos,
    );

    // Exactly one MORE create than the journey's own: the SOS emergency
    // session. The journey's share was stopped first.
    expect(f.api.createCalls, 2);
    expect(f.api.lastCreateInterval, LiveUpdateInterval.sos);
    expect(f.api.lastToken, isNot(journeyToken));
    expect(f.api.stoppedTokens, contains(journeyToken));

    final live = f.container.read(liveLocationControllerProvider);
    expect(live.status, LiveSessionStatus.active);
    expect(live.session, isNotNull);
  });

  test('escalation while still STARTING closes the ledger honestly',
      () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    f.container.read(journeyControllerProvider);

    // Begin a start whose live creation never completes in time: fire SOS
    // between the ledger start and the awaited backend answer.
    final notifier = f.container.read(journeyControllerProvider.notifier);
    final starting = notifier.startJourney();
    f.armSos();
    await starting;

    final state = f.state;
    if (state is JourneyCompleted) {
      expect(state.reason, JourneyEndReason.escalatedToSos);
    } else {
      expect(state, isA<JourneyActive>(),
          reason: 'start won the race; escalation already passed');
    }
  });

  test('an unconfigured build refuses to start with an honest notice',
      () async {
    final sos = createSosContainer(extraOverrides: [
      liveLocationApiClientProvider
          .overrideWithValue(FakeLiveLocationApiClient()),
    ]);
    addTearDown(sos.container.dispose);
    sos.container.read(journeyControllerProvider);

    await sos.container
        .read(journeyControllerProvider.notifier)
        .startJourney();

    final state = sos.container.read(journeyControllerProvider);
    expect(state, isA<JourneyIdle>());
    expect((state as JourneyIdle).notice, contains('could not start'));
  });

  test('"Arrived" ends the journey, stops its share, dismisses cleanly',
      () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney();
    final token = f.api.lastToken;

    await notifier.endJourney();
    await Future<void>.delayed(Duration.zero);

    final state = f.state;
    expect(state, isA<JourneyCompleted>());
    expect((state as JourneyCompleted).reason, JourneyEndReason.arrived);
    expect(f.api.stoppedTokens, contains(token));

    notifier.dismissCompletion();
    expect(f.state, const JourneyIdle());
  });

  test('a lapsed share window flags the journey but does NOT end it',
      () => fakeAsync((async) {
            final f = JourneyFixture();
            addTearDown(f.container.dispose);
            f.container.read(journeyControllerProvider.notifier);

            final starting = f.container
                .read(journeyControllerProvider.notifier)
                .startJourney();
            async.flushMicrotasks();
            expect(starting, completes);
            async.flushMicrotasks();

            // Two hours pass; the live TTL lapses.
            async.elapse(const Duration(hours: 2, seconds: 5));
            async.flushMicrotasks();

            expect(
              f.container.read(liveLocationControllerProvider).status,
              LiveSessionStatus.expired,
            );
            final state = f.state;
            expect(state, isA<JourneyActive>());
            expect((state as JourneyActive).shareExpired, isTrue);

            final ending = f.container
                .read(journeyControllerProvider.notifier)
                .endJourney();
            async.flushMicrotasks();
            expect(ending, completes);
            async.flushMicrotasks();
            expect(
              (f.state as JourneyCompleted).reason,
              JourneyEndReason.arrived,
            );
          }));
}
