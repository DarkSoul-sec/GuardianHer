import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/fake_call/application/fake_call_providers.dart';
import 'package:guardianher/features/fake_call/domain/fake_call_config.dart';
import 'package:guardianher/features/fake_call/domain/fake_call_state.dart';
import 'package:guardianher/features/fake_call/presentation/fake_call_screen.dart';

import '../../helpers/fakes.dart';

ProviderContainer _container({
  FakeFakeCallAlert? alert,
  FakeFakeCallNotifier? notifier,
}) {
  final permissions = FakePermissionService()
    ..statuses[AppPermission.location] = PermissionStatus.granted
    ..statuses[AppPermission.sms] = PermissionStatus.granted
    ..statuses[AppPermission.notifications] = PermissionStatus.granted;
  return createContainer(
    overrides: [
      permissionServiceProvider.overrideWithValue(permissions),
      fakeCallAlertServiceProvider.overrideWithValue(
        alert ?? FakeFakeCallAlert(),
      ),
      fakeCallNotifierProvider.overrideWithValue(
        notifier ?? FakeFakeCallNotifier(),
      ),
    ],
  );
}

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: const FakeCallScreen(),
      routes: const {},
    ),
  );
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
  });

  group('FakeCallScreen', () {
    testWidgets('shows default config: Mom, 10s, vibration on', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Fake Call'), findsWidgets);
      final nameField = tester.widget<TextField>(
        find.byKey(const Key('fake-call-name')),
      );
      expect(nameField.controller!.text, 'Mom');
      expect(find.text('10 seconds'), findsOneWidget);
      expect(find.text('Schedule Fake Call'), findsOneWidget);
    });

    testWidgets('schedule moves to scheduled banner', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule Fake Call'));
      await tester.pumpAndSettle();

      expect(find.text('Fake call scheduled.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        container.read(fakeCallControllerProvider),
        isA<FakeCallScheduled>(),
      );

      // No pending timers at teardown.
      await container.read(fakeCallControllerProvider.notifier).cancelFakeCall();
      await tester.pumpAndSettle();
    });

    testWidgets('ringing shows incoming UI with Answer and Decline',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await container.read(fakeCallControllerProvider.notifier).scheduleFakeCall(
            const FakeCallConfig(callerName: 'Priya'),
          );
      await container
          .read(fakeCallControllerProvider.notifier)
          .showIncomingCall();
      await tester.pumpAndSettle();

      expect(find.text('Priya'), findsWidgets);
      expect(find.text('Simulated incoming call'), findsOneWidget);
      expect(find.byKey(const Key('fake-call-answer')), findsOneWidget);
      expect(find.byKey(const Key('fake-call-decline')), findsOneWidget);

      // No pending timers at teardown.
      await container.read(fakeCallControllerProvider.notifier).declineCall();
      await tester.pumpAndSettle();
    });

    testWidgets('answer shows active timer and End Call', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final notifier = container.read(fakeCallControllerProvider.notifier);
      await notifier.scheduleFakeCall(const FakeCallConfig());
      await notifier.showIncomingCall();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fake-call-answer')));
      await tester.pumpAndSettle();

      expect(find.text('Simulated call'), findsWidgets);
      expect(find.byKey(const Key('fake-call-end')), findsOneWidget);
      expect(
        container.read(fakeCallControllerProvider),
        isA<FakeCallActive>(),
      );

      // Stop the per-second ticker before teardown.
      await container.read(fakeCallControllerProvider.notifier).endCall();
      await tester.pumpAndSettle();
    });

    testWidgets('decline returns to ended banner', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final notifier = container.read(fakeCallControllerProvider.notifier);
      await notifier.scheduleFakeCall(const FakeCallConfig());
      await notifier.showIncomingCall();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fake-call-decline')));
      await tester.pumpAndSettle();

      expect(find.text('Fake call declined.'), findsOneWidget);
      expect(
        container.read(fakeCallControllerProvider),
        isA<FakeCallEnded>(),
      );
    });

    testWidgets('navigates to /fake-call via router', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.fakeCall);
      await tester.pumpAndSettle();

      expect(find.byType(FakeCallScreen), findsOneWidget);
    });
  });
}
