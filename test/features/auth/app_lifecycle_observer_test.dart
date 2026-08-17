import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/app/app.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('locks immediately when the app leaves the foreground',
      (tester) async {
    final container = createContainer(
      overrides: [
        appLockControllerProvider.overrideWith(UnlockedAppLockController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GuardianHerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(appLockControllerProvider).isUnlocked, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(container.read(appLockControllerProvider).isUnlocked, isFalse);
  });

  testWidgets('does not lock when the background time is below the delay',
      (tester) async {
    final prefs = FakePreferencesService();
    await prefs.setString('settings_lock_delay', 'oneMinute');

    final container = createContainer(
      overrides: [
        preferencesServiceProvider.overrideWithValue(prefs),
        appLockControllerProvider.overrideWith(UnlockedAppLockController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GuardianHerApp(),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(container.read(appLockControllerProvider).isUnlocked, isTrue);
  });

  testWidgets('never locks when configured to never lock', (tester) async {
    final prefs = FakePreferencesService();
    await prefs.setString('settings_lock_delay', 'never');

    final container = createContainer(
      overrides: [
        preferencesServiceProvider.overrideWithValue(prefs),
        appLockControllerProvider.overrideWith(UnlockedAppLockController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GuardianHerApp(),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(container.read(appLockControllerProvider).isUnlocked, isTrue);
  });
}