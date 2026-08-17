import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/data/secure_storage_app_lock_repository.dart';
import 'package:guardianher/features/auth/domain/app_lock_status.dart';
import 'package:guardianher/features/auth/presentation/lock_screen.dart';
import 'package:guardianher/features/auth/presentation/widgets/reset_lock.dart';

import '../../helpers/fakes.dart';

void main() {
  Future<FakeSecureStorageService> seededStorage() async {
    final storage = FakeSecureStorageService();
    final stored = await TestPinHasher().hashPin('123456');
    await storage.write(AppLockStorageKeys.pin, stored.encode());
    await storage.write('protected_note', 'secret-value');
    return storage;
  }

  Future<FakePreferencesService> biometricPrefs() async {
    final prefs = FakePreferencesService();
    await prefs.setBool('settings_biometric_enabled', true);
    await prefs.setString('protected_setting', 'kept');
    return prefs;
  }

  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LockScreen()),
    );
  }

  group('Forgot PIN reset flow', () {
    testWidgets(
        'without biometrics the reset is destructive and wipes all local data',
        (tester) async {
      final storage = await seededStorage();
      final prefs = FakePreferencesService();
      await prefs.setString('protected_setting', 'kept');
      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(
            overrides: [
              secureStorageServiceProvider.overrideWithValue(storage),
              preferencesServiceProvider.overrideWithValue(prefs),
            ],
          ),
          pinHasherProvider.overrideWithValue(TestPinHasher()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your local data?'), findsOneWidget);
      expect(find.text(kDestructiveResetWarning), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete & Reset'));
      await tester.pumpAndSettle();

      expect(await storage.containsKey(AppLockStorageKeys.pin), isFalse);
      expect(await storage.read('protected_note'), isNull);
      expect(await prefs.getString('protected_setting'), isNull);
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.needsSetup,
      );
    });

    testWidgets(
        'with biometric verification the reset keeps other local data intact',
        (tester) async {
      final storage = await seededStorage();
      final prefs = await biometricPrefs();
      final cleanup = FakeDataCleanupService();
      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(
            biometricsAvailable: true,
            overrides: [
              secureStorageServiceProvider.overrideWithValue(storage),
              preferencesServiceProvider.overrideWithValue(prefs),
              dataCleanupServiceProvider.overrideWithValue(cleanup),
            ],
          ),
          pinHasherProvider.overrideWithValue(TestPinHasher()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();
      expect(find.text('Enter your PIN'), findsOneWidget);

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset app lock?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your PIN'), findsNothing);
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.needsSetup,
      );
      expect(await storage.containsKey(AppLockStorageKeys.pin), isFalse);
      expect(await storage.read('protected_note'), 'secret-value');
      expect(await prefs.getString('protected_setting'), 'kept');
      expect(cleanup.calls, 0);
    });

    testWidgets('cancelling the destructive dialog keeps everything',
        (tester) async {
      final storage = await seededStorage();
      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(
            overrides: [
              secureStorageServiceProvider.overrideWithValue(storage),
            ],
          ),
          pinHasherProvider.overrideWithValue(TestPinHasher()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await storage.containsKey(AppLockStorageKeys.pin), isTrue);
      expect(await storage.read('protected_note'), 'secret-value');
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.locked,
      );
    });
  });
}