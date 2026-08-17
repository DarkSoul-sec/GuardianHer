import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/app/home_screen.dart';
import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/app/theme/app_theme.dart';
import 'package:guardianher/features/permissions/presentation/permissions_screen.dart';
import 'package:guardianher/features/sos/presentation/sos_screen.dart';

Widget _harness() => const ProviderScope(child: GuardianHerApp());

void main() {
  group('GuardianHerApp', () {
    testWidgets('application starts and renders the app shell', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.byType(ProviderScope), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('GuardianHer'), findsWidgets);
    });

    testWidgets('router navigates to a full-screen feature', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('SOS'));
      await tester.pumpAndSettle();

      expect(find.byType(SosScreen), findsOneWidget);
    });

    testWidgets('router navigates programmatically via GoRouter', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const GuardianHerApp()),
      );
      await tester.pumpAndSettle();

      router.go(AppRoutes.permissions);
      await tester.pumpAndSettle();

      expect(find.byType(PermissionsScreen), findsOneWidget);
    });

    testWidgets('light theme is Material 3', (tester) async {
      await tester.pumpWidget(_harness());
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
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });
  });
}