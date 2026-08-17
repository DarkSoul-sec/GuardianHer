import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/data/secure_storage_app_lock_repository.dart';
import 'package:guardianher/features/auth/presentation/lock_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  Future<FakeSecureStorageService> seededStorage(String pin) async {
    final storage = FakeSecureStorageService();
    final stored = await TestPinHasher().hashPin(pin);
    await storage.write(AppLockStorageKeys.pin, stored.encode());
    return storage;
  }

  Future<FakePreferencesService> biometricPrefs([bool enabled = true]) async {
    final prefs = FakePreferencesService();
    await prefs.setBool('settings_biometric_enabled', enabled);
    return prefs;
  }

  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LockScreen()),
    );
  }

  ProviderContainer containerWith(
    List<Override> overrides, {
    bool biometricsAvailable = false,
  }) {
    return ProviderContainer(
      overrides: [
        ...defaultOverrides(
          biometricsAvailable: biometricsAvailable,
          overrides: overrides,
        ),
        pinHasherProvider.overrideWithValue(TestPinHasher()),
      ],
    );
  }

  group('LockScreen', () {
    testWidgets('shows PIN setup on first launch', (tester) async {
      final container = containerWith([]);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Create PIN'), findsOneWidget);
      expect(find.text('Confirm PIN'), findsOneWidget);
    });

    testWidgets('setup with a matching PIN unlocks', (tester) async {
      final container = containerWith([]);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '123456');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();

      expect(find.text('Create PIN'), findsNothing);
      expect(container.read(appLockControllerProvider).isUnlocked, isTrue);
    });

    testWidgets('setup with a mismatched PIN shows an error', (tester) async {
      final container = containerWith([]);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '123456');
      await tester.enterText(find.byType(TextField).at(1), '999999');
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();

      expect(find.text('The PINs do not match.'), findsOneWidget);
      expect(container.read(appLockControllerProvider).isUnlocked, isFalse);
    });

    testWidgets('unlocks with the correct stored PIN', (tester) async {
      final storage = await seededStorage('123456');
      final container = containerWith([
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your PIN'), findsNothing);
      expect(container.read(appLockControllerProvider).isUnlocked, isTrue);
    });

    testWidgets('shows an error for an incorrect PIN', (tester) async {
      final storage = await seededStorage('123456');
      final container = containerWith([
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect PIN.'), findsOneWidget);
      expect(container.read(appLockControllerProvider).isUnlocked, isFalse);
    });

    testWidgets('offers a biometric shortcut when enabled', (tester) async {
      final storage = await seededStorage('123456');
      final prefs = await biometricPrefs(true);
      final container = containerWith([
        secureStorageServiceProvider.overrideWithValue(storage),
        preferencesServiceProvider.overrideWithValue(prefs),
      ], biometricsAvailable: true);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Use biometrics'), findsOneWidget);
    });

    testWidgets('shows the recovery path when data is corrupted',
        (tester) async {
      final storage = FakeSecureStorageService();
      await storage.write(AppLockStorageKeys.pin, 'garbage');
      final container = containerWith([
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      expect(find.text('Security data unavailable'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reset app lock'), findsOneWidget);
    });
  });
}