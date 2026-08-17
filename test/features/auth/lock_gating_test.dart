import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/app/home_screen.dart';
import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/data/secure_storage_app_lock_repository.dart';
import 'package:guardianher/features/auth/presentation/lock_screen.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

import '../../helpers/fakes.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const GuardianHerApp(),
  );
}

/// Container whose app lock is locked (a PIN is stored but not unlocked).
Future<ProviderContainer> _lockedContainer() async {
  final storage = FakeSecureStorageService();
  final stored = await TestPinHasher().hashPin('123456');
  await storage.write(AppLockStorageKeys.pin, stored.encode());
  return ProviderContainer(
    overrides: [
      ...defaultOverrides(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      ),
      pinHasherProvider.overrideWithValue(TestPinHasher()),
    ],
  );
}

/// Container whose app lock is already unlocked (boots into the shell).
ProviderContainer _unlockedContainer() {
  return createContainer(
    overrides: [
      appLockControllerProvider.overrideWith(UnlockedAppLockController.new),
      pinHasherProvider.overrideWithValue(TestPinHasher()),
    ],
  );
}

void main() {
  group('lock gating', () {
    testWidgets('deep links to protected routes redirect to the lock screen',
        (tester) async {
      final container = await _lockedContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);

      router.go(AppRoutes.sos);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(SosScreen), findsNothing);
    });

    testWidgets('no protected route is reachable before unlock', (tester) async {
      final container = await _lockedContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      for (final route in [
        AppRoutes.home,
        AppRoutes.contacts,
        AppRoutes.history,
        AppRoutes.settings,
        AppRoutes.profile,
        AppRoutes.sos,
        AppRoutes.location,
        AppRoutes.permissions,
        AppRoutes.security,
        AppRoutes.changePin,
        AppRoutes.privacyPolicy,
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          find.byType(LockScreen),
          findsOneWidget,
          reason: '$route must redirect to the lock screen while locked',
        );
      }
    });

    testWidgets('relocking cannot be bypassed by navigation', (tester) async {
      final container = _unlockedContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      container.read(appLockControllerProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      final router = container.read(appRouterProvider);
      router.go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  });
}