import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/journey/application/emergency_vehicle_context.dart';
import 'package:guardianher/features/journey/application/journey_providers.dart';
import 'package:guardianher/features/journey/domain/journey_state.dart';
import 'package:guardianher/features/journey/presentation/journey_screen.dart';

import '../../helpers/fakes.dart';
import '../sos/sos_test_fakes.dart';
import 'journey_controller_test.dart';

/// Widget tests must not end with pending timers: end any
/// active session and stop whatever share is still running.
Future<void> tearJourneyDown(JourneyFixture f, WidgetTester tester) async {
  final state = f.state;
  if (state.isActiveLike) {
    await f.container.read(journeyControllerProvider.notifier).endJourney();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_done': true,
    });
  });

  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: JourneyScreen()),
    );
  }

  testWidgets('the start form treats vehicle info as optional', (tester) async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    f.container.read(journeyControllerProvider);
    await tester.pumpWidget(harness(f.container));

    expect(find.text('Start safe journey'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journey-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(f.state, isA<JourneyActive>());
    await tearJourneyDown(f, tester);
  });

  testWidgets('a vehicle is entered in seconds and shown while travelling',
      (tester) async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    f.container.read(journeyControllerProvider);
    await tester.pumpWidget(harness(f.container));

    // Type defaults to the fast path (Taxi); only the number is typed.
    await tester.enterText(
      find.byKey(const Key('journey-vehicle-registration')),
      'dl-01-ab-1234',
    );
    await tester.tap(find.byKey(const Key('journey-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final state = f.state as JourneyActive;
    expect(state.vehicle?.registrationNumber, 'DL01AB1234');

    // Active view renders the friendly display format.
    expect(find.textContaining('Journey running'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('DL 01 AB 1234'), findsOneWidget);
    expect(find.byKey(const Key('journey-share-button')), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
    await tearJourneyDown(f, tester);
  });

  testWidgets('an invalid registration shows a clear error and blocks start',
      (tester) async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    f.container.read(journeyControllerProvider);
    await tester.pumpWidget(harness(f.container));

    await tester.enterText(
      find.byKey(const Key('journey-vehicle-registration')),
      'DL##12@@',
    );
    await tester.tap(find.byKey(const Key('journey-start')));
    await tester.pump();

    expect(find.text('Check the vehicle number.'), findsOneWidget);
    expect(f.state, isA<JourneyIdle>());
  });

  testWidgets('an active journey can end and the summary shows the vehicle',
      (tester) async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney(
      vehicle: const VehicleInfo(type: VehicleType.taxi),
    );
    await tester.pumpWidget(harness(f.container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('journey-end')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Journey ended'), findsOneWidget);
    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Start:'), findsNothing,
        reason: 'start/end render as one combined line');
    expect(find.textContaining('Start:'), findsOneWidget);
    expect(find.textContaining('End:'), findsOneWidget);
    expect(find.byKey(const Key('journey-dismiss')), findsOneWidget);

    // Requirement K/M: dismissing releases everything; form comes back empty.
    await tester.tap(find.byKey(const Key('journey-dismiss')));
    await tester.pump();
    expect(
      f.container.read(emergencyVehicleContextProvider),
      isNull,
    );
    final registrationField = tester.widget<TextField>(
      find.byKey(const Key('journey-vehicle-registration')),
    );
    expect(registrationField.controller!.text, isEmpty);
    await tearJourneyDown(f, tester);
  });

  testWidgets('an escalated journey explains the handover, not success',
      (tester) async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    final notifier = f.container.read(journeyControllerProvider.notifier);
    await notifier.startJourney();

    f.armSos();
    await tester.pumpWidget(harness(f.container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Emergency took over your journey'),
      findsOneWidget,
    );
    expect(find.textContaining('emergency alert is running'), findsOneWidget);
    expect(find.byKey(const Key('journey-dismiss')), findsOneWidget);

    await tester.tap(find.byKey(const Key('journey-dismiss')));
    await tester.pump();

    // Back to a clean form after the banner is dismissed.
    expect(find.text('Start safe journey'), findsOneWidget);
    expect(f.state, const JourneyIdle());
    await tearJourneyDown(f, tester);
  });

  testWidgets('a refused start shows the honest notice on the form',
      (tester) async {
    final f = JourneyFixture();
    addTearDown(f.container.dispose);
    // Set up SOS active to trigger the refused start
    f.container.read(journeyControllerProvider);
    f.armSos();
    await tester.pumpWidget(harness(f.container));
    await tester.pump();

    await tester.tap(find.byKey(const Key('journey-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('An emergency is active'), findsOneWidget);
    expect(f.state, isA<JourneyIdle>());
  });
}