import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/settings/application/settings_providers.dart';
import 'package:guardianher/features/settings/domain/app_lock_delay.dart';
import 'package:guardianher/features/settings/domain/settings_failures.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakePreferencesService preferences;
  late FakeBiometricService biometrics;

  ProviderContainer container() {
    preferences = FakePreferencesService();
    biometrics = FakeBiometricService();
    return ProviderContainer(
      overrides: [
        ...defaultOverrides(
          biometricsAvailable: false,
          overrides: [
            preferencesServiceProvider.overrideWithValue(preferences),
            biometricServiceProvider.overrideWithValue(biometrics),
          ],
        ),
      ],
    );
  }

  Future<void> settle(ProviderContainer c) async {
    // Let the async _load() complete.
    await Future<void>.delayed(Duration.zero);
    await c.pump();
  }

  group('SecuritySettingsController', () {
    test('defaults to biometrics off and immediate lock', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);

      final settings = c.read(securitySettingsControllerProvider);
      expect(settings.biometricEnabled, isFalse);
      expect(settings.lockDelay, AppLockDelay.immediate);
    });

    test('setLockDelay persists and updates state', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(securitySettingsControllerProvider.notifier)
          .setLockDelay(AppLockDelay.fiveMinutes);

      expect(result, isA<Ok>());
      expect(c.read(securitySettingsControllerProvider).lockDelay,
          AppLockDelay.fiveMinutes);
      expect(
        await preferences.getString('settings_lock_delay'),
        'fiveMinutes',
      );
    });

    test('enabling biometrics requires a successful verification', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      biometrics.authenticateResult = const Ok(true);
      await settle(c);

      final result = await c
          .read(securitySettingsControllerProvider.notifier)
          .setBiometricEnabled(true);

      expect(result, isA<Ok>());
      expect(c.read(securitySettingsControllerProvider).biometricEnabled, isTrue);
      expect(
        await preferences.getBool('settings_biometric_enabled'),
        isTrue,
      );
    });

    test('rejects enabling biometrics when verification is declined', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      biometrics.authenticateResult = const Ok(false);
      await settle(c);

      final result = await c
          .read(securitySettingsControllerProvider.notifier)
          .setBiometricEnabled(true);

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<BiometricSetupFailure>());
      expect(c.read(securitySettingsControllerProvider).biometricEnabled, isFalse);
    });

    test('rejects enabling biometrics when unavailable', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = false;
      await settle(c);

      final result = await c
          .read(securitySettingsControllerProvider.notifier)
          .setBiometricEnabled(true);

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<BiometricSetupFailure>());
    });

    test('disabling biometrics needs no verification', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);
      await c
          .read(securitySettingsControllerProvider.notifier)
          .setBiometricEnabled(true);

      final result = await c
          .read(securitySettingsControllerProvider.notifier)
          .setBiometricEnabled(false);

      expect(result, isA<Ok>());
      expect(c.read(securitySettingsControllerProvider).biometricEnabled, isFalse);
    });
  });
}