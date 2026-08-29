import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/app/home_screen.dart';
import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/app/theme/app_theme.dart';
import 'package:guardianher/features/contacts/presentation/contact_form_screen.dart';
import 'package:guardianher/features/contacts/presentation/contacts_screen.dart';
import 'package:guardianher/features/permissions/presentation/permissions_screen.dart';
import 'package:guardianher/features/settings/presentation/settings_screen.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

import '../helpers/fakes.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const GuardianHerApp(),
  );
}

ProviderContainer _container() {
  return createContainer();
}

void main() {
  group('GuardianHerApp', () {
    testWidgets('opens directly to Home without any lock screen',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      // No authentication gate: no PIN, biometric or lock UI of any kind.
      expect(find.textContaining('PIN'), findsNothing);
      expect(find.textContaining('Unlock'), findsNothing);
      expect(find.textContaining('Biometric'), findsNothing);
    });

    testWidgets('router navigates to a full-screen feature', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SOS'));
      await tester.pumpAndSettle();

      expect(find.byType(SosScreen), findsOneWidget);
    });

    testWidgets('router navigates programmatically via GoRouter',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      router.go(AppRoutes.permissions);
      await tester.pumpAndSettle();

      expect(find.byType(PermissionsScreen), findsOneWidget);
    });

    testWidgets('deep links open without any authentication gate',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final destinations = <String, Type>{
        AppRoutes.contacts: ContactsScreen,
        AppRoutes.contactsAdd: AddContactScreen,
        AppRoutes.contactsEdit('any'): EditContactScreen,
        AppRoutes.sos: SosScreen,
        AppRoutes.permissions: PermissionsScreen,
        AppRoutes.settings: SettingsScreen,
      };
      for (final entry in destinations.entries) {
        container.read(appRouterProvider).go(entry.key);
        await tester.pumpAndSettle();
        expect(
          find.byType(entry.value),
          findsOneWidget,
          reason: '${entry.key} must render ${entry.value} without a lock gate',
        );
      }
    });

    testWidgets('the app shell persists across background/resume',
        (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final lifecycle = tester.binding;
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      lifecycle.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // No lock screen appears after backgrounding/resuming.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('dark theme is Material 3', (tester) async {
      final container = _container();
      addTearDown(container.dispose);

      await tester.pumpWidget(_harness(container));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(NavigationBar));
      final theme = Theme.of(context);
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
    });

    test('AppTheme provides light and dark variants', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });

    test('appRouterProvider resolves a configured GoRouter', () {
      final container = _container();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
      // The router starts on Home; there is no lock route anymore.
      expect(router.routeInformationProvider.value.uri.path,
          AppRoutes.home);
    });
  });
}