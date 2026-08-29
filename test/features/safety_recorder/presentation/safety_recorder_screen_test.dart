import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/journey/domain/safety_recorder_events.dart';
import 'package:guardianher/features/journey/domain/vehicle_info.dart';
import 'package:guardianher/features/safety_recorder/application/safety_recorder_controller.dart';
import 'package:guardianher/features/safety_recorder/data/safety_incident_repository.dart';
import 'package:guardianher/features/safety_recorder/domain/safety_incident.dart';
import 'package:guardianher/features/safety_recorder/presentation/safety_recorder_screen.dart';
import 'package:guardianher/features/safety_recorder/presentation/safety_incident_detail_screen.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/application/sos_state.dart';

import '../../../helpers/fakes.dart';
import '../safety_recorder_test_helpers.dart';

/// Fake repo that returns a scripted list of incidents.
class _FakeSafetyIncidentRepository implements SafetyIncidentRepository {
  List<SafetyIncident> incidents = [];

  @override
  Future<Result<List<SafetyIncident>>> loadAll() async =>
      Ok(List.unmodifiable(incidents));

  @override
  Future<Result<void>> save(SafetyIncident incident) async {
    incidents.add(incident);
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    incidents.removeWhere((i) => i.id == id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> clearAll() async {
    incidents.clear();
    return const Ok(null);
  }
}

/// Wraps a widget in a MaterialApp + theme for rendering.
Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      ...defaultOverrides(),
      ...safetyRecorderTestOverrides(),
      ...overrides,
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('SafetyRecorderScreen', () {
    testWidgets('shows empty state when no incidents exist', (tester) async {
      await tester.pumpWidget(_wrap(const SafetyRecorderScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No Safety Incidents'), findsOneWidget);
      expect(
        find.text(
          'Incidents are recorded automatically during\nSOS activations and safety sessions.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('shows incident list when incidents exist', (tester) async {
      final repo = _FakeSafetyIncidentRepository();
      repo.incidents = [
        createTestIncident(id: 'i1', createdAt: DateTime.utc(2026, 3, 15, 10, 30)),
        createTestIncident(id: 'i2', createdAt: DateTime.utc(2026, 3, 14, 8, 0)),
      ];

      await tester.pumpWidget(
        _wrap(
          const SafetyRecorderScreen(),
          overrides: [
            safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Safety Incidents'), findsNothing);
      expect(find.text('COMPLETED'), findsOneWidget);
      // Should show event count for each incident.
      expect(find.text('1 event'), findsNWidgets(2));
    });

    testWidgets('shows active incident in Recording section', (tester) async {
      final repo = _FakeSafetyIncidentRepository();
      final manualSos = ManualSosController();
      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(),
          safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ...safetyRecorderTestOverrides(manualSos: manualSos),
        ],
      );
      addTearDown(container.dispose);
      // Attach the notifier to the container.
      container.read(sosControllerProvider.notifier);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SafetyRecorderScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger SOS through the container-attached notifier.
      (container.read(sosControllerProvider.notifier) as ManualSosController)
          .activate();
      await tester.pumpAndSettle();

      expect(find.text('RECORDING'), findsOneWidget);
    });

    testWidgets('shows vehicle type when present on incident', (tester) async {
      final repo = _FakeSafetyIncidentRepository();
      final incident = createTestIncident(id: 'v1');
      // Simulate vehicle attachment metadata.
      final withVehicle = incident.copyWith(
        vehicleType: VehicleType.taxi,
        hasVehicleRegistration: true,
      );
      repo.incidents = [withVehicle];

      await tester.pumpWidget(
        _wrap(
          const SafetyRecorderScreen(),
          overrides: [
            safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Vehicle'), findsOneWidget);
    });
  });

  group('SafetyIncidentDetailScreen', () {
    testWidgets('shows header with date and event count', (tester) async {
      final incident = createTestIncident(
        id: 'detail1',
        createdAt: DateTime.utc(2026, 5, 20, 14, 30),
        eventTypes: [
          SafetyEventType.sosActivated,
          SafetyEventType.locationCaptured,
          SafetyEventType.sosCompleted,
        ],
      );

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: incident)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Incident Details'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // event count
      expect(find.text('events'), findsOneWidget);
    });

    testWidgets('shows integrity section', (tester) async {
      final incident = createTestIncident(id: 'integrity1');

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: incident)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Integrity'), findsOneWidget);
      // Genesis hash should be displayed (truncated).
      expect(find.textContaining('guardianher-reco'), findsOneWidget);
    });

    testWidgets('shows Verified badge for valid chain', (tester) async {
      final incident = createTestIncident(
        id: 'valid',
        eventTypes: [
          SafetyEventType.sosActivated,
          SafetyEventType.sosCompleted,
        ],
      );

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: incident)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Integrity'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget); // verified chip
    });

    testWidgets('shows event timeline with correct labels', (tester) async {
      final incident = createTestIncident(
        id: 'timeline',
        eventTypes: [
          SafetyEventType.sosActivated,
          SafetyEventType.locationCaptured,
          SafetyEventType.communicationHandedOff,
          SafetyEventType.sosCompleted,
        ],
      );

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: incident)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Event Timeline'), findsOneWidget);
      expect(find.text('SOS activated'), findsOneWidget);
      expect(find.text('Location captured'), findsOneWidget);
      expect(find.text('Communication handed off'), findsOneWidget);
      expect(find.text('SOS completed'), findsOneWidget);
    });

    testWidgets('shows vehicle section when vehicle attached', (tester) async {
      final incident = createTestIncident(id: 'veh');
      final withVehicle = incident.copyWith(
        vehicleType: VehicleType.cab,
        hasVehicleRegistration: true,
      );

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: withVehicle)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vehicle Information'), findsOneWidget);
      expect(find.textContaining('Cab'), findsOneWidget);
      expect(find.textContaining('redacted'), findsOneWidget);
    });

    testWidgets('does not show vehicle section when no vehicle',
        (tester) async {
      final incident = createTestIncident(id: 'noveh');

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: incident)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vehicle Information'), findsNothing);
    });

    testWidgets('shows delete button for completed incident', (tester) async {
      final incident = createTestIncident(id: 'del');
      final repo = _FakeSafetyIncidentRepository();
      repo.incidents = [incident];

      await tester.pumpWidget(
        _wrap(
          SafetyIncidentDetailScreen(incident: incident),
          overrides: [
            safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('does not show delete button for active incident',
        (tester) async {
      final incident = createTestIncident(
        id: 'active_del',
        status: SafetyIncidentStatus.recording,
      );

      await tester.pumpWidget(
        _wrap(SafetyIncidentDetailScreen(incident: incident)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('delete confirmation dialog appears on tap', (tester) async {
      final incident = createTestIncident(id: 'confirm_del');
      final repo = _FakeSafetyIncidentRepository();
      repo.incidents = [incident];

      await tester.pumpWidget(
        _wrap(
          SafetyIncidentDetailScreen(incident: incident),
          overrides: [
            safetyIncidentRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Incident'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
