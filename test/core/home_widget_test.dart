import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/platform/home_widget.dart';

void main() {
  group('isSosWidgetUri', () {
    test('recognizes the widget launch URI', () {
      expect(isSosWidgetUri(Uri.parse('guardianher://sos')), isTrue);
      expect(isSosWidgetUri(Uri.parse('guardianher://sos/path')), isTrue);
    });

    test('rejects null and unrelated URIs', () {
      expect(isSosWidgetUri(null), isFalse);
      expect(isSosWidgetUri(Uri.parse('guardianher://check-in')), isFalse);
      expect(isSosWidgetUri(Uri.parse('guardianher://shakesos')), isFalse);
      expect(isSosWidgetUri(Uri.parse('https://example.com')), isFalse);
    });
  });

  group('isShakeSosUri', () {
    test('recognizes the shake-triggered SOS URI', () {
      expect(isShakeSosUri(Uri.parse('guardianher://shakesos')), isTrue);
    });

    test('rejects null and unrelated URIs', () {
      expect(isShakeSosUri(null), isFalse);
      expect(isShakeSosUri(Uri.parse('guardianher://sos')), isFalse);
      expect(isShakeSosUri(Uri.parse('guardianher://check-in')), isFalse);
      expect(isShakeSosUri(Uri.parse('https://example.com')), isFalse);
    });
  });

  group('isTileSosUri', () {
    test('recognizes the QS tile SOS URI', () {
      expect(isTileSosUri(Uri.parse('guardianher://tilesos')), isTrue);
    });

    test('rejects null and unrelated URIs', () {
      expect(isTileSosUri(null), isFalse);
      expect(isTileSosUri(Uri.parse('guardianher://sos')), isFalse);
      expect(isTileSosUri(Uri.parse('guardianher://shakesos')), isFalse);
      expect(isTileSosUri(Uri.parse('https://example.com')), isFalse);
    });
  });

  group('routeWidgetLaunch', () {
    GoRouter buildRouter() {
      return GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.sos,
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      );
    }

    Future<void> pumpRouter(WidgetTester tester, GoRouter router) async {
      publishedRouter = router;
      addTearDown(() => publishedRouter = null);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    }

    testWidgets('routes to SOS and arms when the widget was tapped', (tester) async {
      final router = buildRouter();
      await pumpRouter(tester, router);

      var armed = false;
      routeLaunch(Uri.parse('guardianher://sos'), (uri) => armed = true);
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.sos);
      expect(armed, isTrue);
    });

    testWidgets('routes to SOS and arms on a QS tile URI', (tester) async {
      final router = buildRouter();
      await pumpRouter(tester, router);

      var armed = false;
      routeLaunch(Uri.parse('guardianher://tilesos'), (uri) => armed = true);
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.sos);
      expect(armed, isTrue);
    });

    testWidgets('routes to SOS and arms on a shake URI', (tester) async {
      final router = buildRouter();
      await pumpRouter(tester, router);

      var armed = false;
      routeLaunch(Uri.parse('guardianher://shakesos'), (uri) => armed = true);
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.sos);
      expect(armed, isTrue);
    });

    testWidgets('ignores non-widget launches', (tester) async {
      final router = buildRouter();
      await pumpRouter(tester, router);

      routeWidgetLaunch(null);
      routeWidgetLaunch(Uri.parse('https://example.com'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.home,
      );
    });
  });
}
