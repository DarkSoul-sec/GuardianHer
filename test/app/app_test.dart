import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/app/home_screen.dart';
import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/app/theme/app_theme.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/presentation/lock_screen.dart';
import 'package:guardianher/features/permissions/presentation/permissions_screen.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

import '../helpers/fakes.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const GuardianHerApp(),
  );
}

/// Container whose app lock is already unlocked, so the app boots into the
/// shell without going through PIN setup.
ProviderContainer _unlockedContainer() {
  return createContainer(
    overrides: [
      appLockControllerProvider.overrideWith(UnlockedAppLockController.new),
    ],
  );
}

void main() {
  group('GuardianHerApp', () {
    testWidgets('starts locked and requires PIN setup before the shell',
        (tester) async {
      final container = createContainer(
        overrides: [pinHasherProvider.overrideWithValue(TestPinHasher())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Create PIN'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), '123456');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('boots into the app shell when already unlocked',
        (tester) async {
      final container = _unlockedContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('GuardianHer'), findsWidgets);
    });

    testWidgets('router navigates to a full-screen feature', (tester) async {
      final container = _unlockedContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SOS'));
      await tester.pumpAndSettle();

      expect(find.byType(SosScreen), findsOneWidget);
    });

    testWidgets('router navigates programmatically via GoRouter',
        (tester) async {
      final container = _unlockedContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      router.go(AppRoutes.permissions);
      await tester.pumpAndSettle();

      expect(find.byType(PermissionsScreen), findsOneWidget);
    });

    testWidgets('security settings are reachable from the home screen',
        (tester) async {
      final container = _unlockedContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();

      expect(find.text('Biometric unlock'), findsOneWidget);
      expect(find.text('Change PIN'), findsOneWidget);
    });

    testWidgets('light theme is Material 3', (tester) async {
      final container = _unlockedContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(NavigationBar));
      final theme = Theme.of(context);
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
    });

    test('AppTheme provides light and dark variants', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });

    test('appRouterProvider resolves a configured GoRouter', () {
      final container = _unlockedContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });
  });
}