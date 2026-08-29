import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/sos/application/sos_providers.dart';
import 'package:guardianher/features/sos/domain/sos_event.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

import '../../helpers/fakes.dart';
import 'sos_test_fakes.dart';

ProviderContainer _container() {
  return createContainer(
    overrides: [
      sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
      sosEventIdGeneratorProvider.overrideWithValue(() => SosEventId(testSosEventId)),
      vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      callServiceProvider.overrideWithValue(FakeCallService()),
      smsServiceProvider.overrideWithValue(FakeSmsService()),
    ],
  );
}

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SosScreen()),
  );
}

void main() {
  group('SosScreen', () {
    testWidgets('shows the idle SOS launch view', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container));

      expect(find.text('Emergency SOS'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'SOS'), findsOneWidget);
    });

    testWidgets('tapping SOS activates the workflow immediately', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container));

      await tester.tap(find.widgetWithText(FilledButton, 'SOS'));
      await tester.pump();

      // No countdown: the workflow is active on the first frame.
      expect(find.text('SOS activates in'), findsNothing);
      expect(find.text('SOS ACTIVE'), findsOneWidget);
      expect(find.text('End SOS'), findsOneWidget);
    });

    testWidgets('a disabled location service offers a one-tap turn-on',
        (tester) async {
      final container = createContainer(
        overrides: [
          sosClockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12)),
          sosEventIdGeneratorProvider.overrideWithValue(
            () => SosEventId(testSosEventId),
          ),
          vibrationServiceProvider.overrideWithValue(FakeVibrationService()),
          notificationServiceProvider.overrideWithValue(FakeNotificationService()),
          callServiceProvider.overrideWithValue(FakeCallService()),
          smsServiceProvider.overrideWithValue(FakeSmsService()),
          locationServiceProvider
              .overrideWithValue(FakeLocationService(enabled: false)),
          permissionServiceProvider.overrideWithValue(
            FakePermissionService()
              ..statuses[AppPermission.location] = PermissionStatus.granted,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container));

      await tester.tap(find.widgetWithText(FilledButton, 'SOS'));
      await tester.pump();
      await tester.pump();

      expect(find.text('SOS ACTIVE'), findsOneWidget);
      expect(
        find.text('Location is turned off'),
        findsOneWidget,
      );
      expect(find.text('Turn on location'), findsOneWidget);

      // End the session so the pending location retry is cancelled before the
      // test ends (no dangling timers).
      container.read(sosControllerProvider.notifier).cancelSos();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('cancelling an active session ends it', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container));

      await tester.tap(find.widgetWithText(FilledButton, 'SOS'));
      await tester.pump();

      await tester.tap(find.text('End SOS'));
      await tester.pump();
      expect(find.text('Stopping SOS…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('SOS session ended'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'SOS'), findsOneWidget);
    });

    testWidgets('ending an active session completes it', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container));

      await tester.tap(find.widgetWithText(FilledButton, 'SOS'));
      await tester.pump();
      expect(find.text('SOS ACTIVE'), findsOneWidget);

      await tester.tap(find.text('End SOS'));
      await tester.pump();
      expect(find.text('Stopping SOS…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('SOS session ended'), findsOneWidget);
    });
  });
}