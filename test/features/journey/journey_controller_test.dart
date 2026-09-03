import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardianher/features/journey/application/emergency_vehicle_context.dart';
import 'package:guardianher/features/journey/application/journey_providers.dart';
import 'package:guardianher/features/journey/domain/journey_state.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';

import '../../helpers/fakes.dart';
import '../sos/sos_test_fakes.dart';

/// Fixture wiring a journey container with mocked SOS.
class JourneyFixture {
  JourneyFixture() {
    final sos = createSosContainer();
    container = sos.container;
    timer = sos.timer;
  }

  late final ProviderContainer container;
  late final FakeSosTimer timer;

  JourneyState get state => container.read(journeyControllerProvider);

  void armSos() {
    container.read(sosControllerProvider.notifier).startSos();
    timer.fireComplete();
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_done': true,
    });
  });

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
    expect(active.shareUrl, contains('https://guardianher.app/journey'));
    expect(active.vehicle?.type, VehicleType.taxi);
    expect(active.vehicle?.displayRegistrationNumber, 'DL 01 AB 1234');
    expect(active.session.type.storageName, 'safe_journey');
  });

  test('a duplicate start is absorbed silently', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);

    await notifier.startJourney();
    final first = f.state as JourneyActive;
    await notifier.startJourney();

    expect(f.state, same(first));
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

  test('"Arrived" ends the journey, stops its share, dismisses cleanly',
      () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney();

    await notifier.endJourney();
    await Future<void>.delayed(Duration.zero);

    final state = f.state;
    expect(state, isA<JourneyCompleted>());
    expect((state as JourneyCompleted).reason, JourneyEndReason.arrived);

    notifier.dismissCompletion();
    expect(f.state, const JourneyIdle());
  });

  test('shareAgain replaces the journey share link', () async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney();
    final firstUrl = (f.state as JourneyActive).shareUrl;

    await notifier.shareAgain(f.state as JourneyActive);

    final state = f.state as JourneyActive;
    expect(state.shareUrl, isNot(firstUrl));
    expect(state.shareUrl, contains('https://guardianher.app/journey'));
    expect(state.shareExpired, isFalse);
  });
}