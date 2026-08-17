import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/error/failures.dart';
import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/data/secure_storage_app_lock_repository.dart';
import 'package:guardianher/features/auth/domain/app_lock_status.dart';
import 'package:guardianher/features/settings/application/privacy_providers.dart';
import 'package:guardianher/features/settings/presentation/settings_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  group('PrivacyController', () {
    test('surfaces a cleanup failure without touching the app lock', () async {
      final cleanup = FakeDataCleanupService(
        result: const Err<void>(StorageFailure('boom')),
      );
      final container = ProviderContainer(
        overrides: [
          ...defaultOverrides(
            overrides: [
              dataCleanupServiceProvider.overrideWithValue(cleanup),
            ],
          ),
          pinHasherProvider.overrideWithValue(TestPinHasher()),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(privacyControllerProvider.notifier)
          .deleteAllLocalData();

      expect(result, isA<Err>());
      expect(cleanup.calls, 1);
    });
  });

  group('SettingsScreen delete flow', () {
    testWidgets('delete all local data confirms and removes the PIN',
        (tester) async {
      final storage = FakeSecureStorageService();
      final stored = await TestPinHasher().hashPin('123456');
      await storage.write(AppLockStorageKeys.pin, stored.encode());

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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete all local data'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all local data?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await storage.containsKey(AppLockStorageKeys.pin), isFalse);
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.needsSetup,
      );
    });

    testWidgets('cancel keeps the PIN', (tester) async {
      final storage = FakeSecureStorageService();
      final stored = await TestPinHasher().hashPin('123456');
      await storage.write(AppLockStorageKeys.pin, stored.encode());

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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete all local data'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await storage.containsKey(AppLockStorageKeys.pin), isTrue);
    });
  });
}