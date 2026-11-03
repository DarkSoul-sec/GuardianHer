import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardianher/app/home_screen.dart';
import 'package:guardianher/app/router/app_router.dart';
import 'package:guardianher/core/permissions/permission_service.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/onboarding/application/permission_onboarding_notifier.dart';
import 'package:guardianher/features/onboarding/application/permission_onboarding_providers.dart';
import 'package:guardianher/features/onboarding/presentation/screens/permission_onboarding_screen.dart';
import 'package:guardianher/shared/widgets/app_shell.dart';

import '../helpers/fakes.dart';

/// Notifier with platform checks disabled: starts fully granted so the
/// Continue action is enabled deterministically in tests.
class _GrantedOnboardingNotifier extends PermissionOnboardingNotifier {
  _GrantedOnboardingNotifier({
    required super.deviceAdminDataSource,
    required super.directSmsService,
    required super.shakeSosService,
    required super.ref,
  });

  @override
  Future<void> refresh() async {}
}

ProviderContainer _container() {
  final permissions = FakePermissionService()
    ..statuses[AppPermission.location] = PermissionStatus.granted
    ..statuses[AppPermission.sms] = PermissionStatus.granted
    ..statuses[AppPermission.notifications] = PermissionStatus.granted;
  return createContainer(
    overrides: [
      permissionServiceProvider.overrideWithValue(permissions),
      permissionOnboardingNotifierProvider.overrideWith((ref) {
        final notifier = _GrantedOnboardingNotifier(
          deviceAdminDataSource: ref.watch(deviceAdminDataSourceProvider),
          directSmsService: ref.watch(directSmsServiceProvider),
          shakeSosService: ref.watch(shakeSosServiceProvider),
          ref: ref,
        );
        notifier.state = PermissionOnboardingState(
          items: notifier.state.items
              .map((i) => i.copyWith(isGranted: true))
              .toList(),
        );
        return notifier;
      }),
    ],
  );
}

void main() {
  setUpAll(() {
    // Fresh install: onboarding has never completed.
    SharedPreferences.setMockInitialValues({});
  });

  group('Onboarding routing', () {
    test('canonical Home route is /', () {
      expect(AppRoutes.home, '/');
    });

    testWidgets(
        'permission setup completion lands on Home, never on /home',
        (tester) async {
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

      // Splash redirects a fresh install to permission setup.
      expect(find.byType(PermissionOnboardingScreen), findsOneWidget);

      await tester.tap(find.text('Continue to GuardianHer'));
      await tester.pumpAndSettle();

      // No GoException ("no routes for location: /home"), Home renders
      // inside the shell with the Home tab selected.
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/');
    });
  });
}
