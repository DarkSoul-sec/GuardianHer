import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/providers.dart';
import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/auth/application/app_lock_providers.dart';
import 'package:guardianher/features/auth/application/app_lock_state.dart';
import 'package:guardianher/features/auth/application/lockout_policy.dart';
import 'package:guardianher/features/auth/application/pin_hasher.dart';
import 'package:guardianher/features/auth/data/secure_storage_app_lock_repository.dart';
import 'package:guardianher/features/auth/domain/app_lock_failures.dart';
import 'package:guardianher/features/auth/domain/app_lock_status.dart';
import 'package:guardianher/features/auth/domain/credential_policy.dart';
import 'package:guardianher/features/auth/domain/lockout_state.dart';
import 'package:guardianher/features/settings/application/settings_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSecureStorageService storage;
  late FakeBiometricService biometrics;

  ProviderContainer container() {
    storage = FakeSecureStorageService();
    biometrics = FakeBiometricService();
    return ProviderContainer(
      overrides: [
        ...defaultOverrides(
          biometricsAvailable: false,
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
            biometricServiceProvider.overrideWithValue(biometrics),
          ],
        ),
        pinHasherProvider.overrideWithValue(TestPinHasher()),
      ],
    );
  }

  Future<AppLockState> settle(ProviderContainer c) async {
    await c.read(appLockControllerProvider.notifier).initialize();
    return c.read(appLockControllerProvider);
  }

  Future<void> seedPin(String pin) async {
    final stored = await TestPinHasher().hashPin(pin);
    await storage.write(AppLockStorageKeys.pin, stored.encode());
  }

  Future<void> enableBiometrics(ProviderContainer c) async {
    await c
        .read(securitySettingsControllerProvider.notifier)
        .setBiometricEnabled(true);
  }

  group('initialization', () {
    test('first launch resolves to needsSetup', () async {
      final c = container();
      addTearDown(c.dispose);

      final state = await settle(c);
      expect(state.status, AppLockStatus.needsSetup);
      expect(state.isUnlocked, isFalse);
    });

    test('stored PIN resolves to locked', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');

      final state = await settle(c);
      expect(state.status, AppLockStatus.locked);
      expect(state.biometricsAvailable, isFalse);
    });

    test('biometric availability is reflected', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      await seedPin('123456');

      final state = await settle(c);
      expect(state.biometricsAvailable, isTrue);
    });

    test('unreadable stored data resolves to corrupted', () async {
      final c = container();
      addTearDown(c.dispose);
      await storage.write(AppLockStorageKeys.pin, 'not-a-valid-encoded-pin');

      final state = await settle(c);
      expect(state.status, AppLockStatus.corrupted);
    });

    test('stored credentials violating the policy resolve to corrupted',
        () async {
      final c = container();
      addTearDown(c.dispose);
      // Credentials created by this test run are normally validated against a
      // relaxed policy; use the production policy so the weak credential
      // below is rejected.
      final cStrict = ProviderContainer(
        overrides: [
          ...defaultOverrides(
            overrides: [
              secureStorageServiceProvider.overrideWithValue(storage),
              biometricServiceProvider.overrideWithValue(biometrics),
              credentialPolicyProvider.overrideWithValue(
                const CredentialPolicy(),
              ),
            ],
          ),
          pinHasherProvider.overrideWithValue(TestPinHasher()),
        ],
      );
      addTearDown(cStrict.dispose);
      // A credential far below the production minimum iteration count.
      final weak = await PinHasher(iterations: 10).hashPin('123456');
      await storage.write(AppLockStorageKeys.pin, weak.encode());

      final state = await settle(cStrict);
      expect(state.status, AppLockStatus.corrupted);
    });

    test('lockout state survives a restart', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      final until = DateTime.now().add(const Duration(seconds: 30));
      await storage.write(
        AppLockStorageKeys.lockout,
        LockoutState(failedAttempts: 0, lockoutUntil: until).encode(),
      );

      final state = await settle(c);
      expect(state.isLockedOut, isTrue);
      expect(state.lockoutRemaining, greaterThan(Duration.zero));
    });
  });

  group('setupPin', () {
    test('creates the PIN and unlocks', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .setupPin(pin: '654321', confirmation: '654321');

      expect(result, isA<Ok>());
      expect(c.read(appLockControllerProvider).status, AppLockStatus.unlocked);
      expect(await storage.containsKey(AppLockStorageKeys.pin), isTrue);
    });

    test('rejects mismatched confirmation', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .setupPin(pin: '654321', confirmation: '999999');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<PinMismatchFailure>());
      expect(c.read(appLockControllerProvider).status, AppLockStatus.needsSetup);
    });

    test('rejects a PIN shorter than 6 digits', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .setupPin(pin: '123', confirmation: '123');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<InvalidPinLengthFailure>());
    });

    test('rejects a PIN longer than 6 digits', () async {
      final c = container();
      addTearDown(c.dispose);
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .setupPin(pin: '1234567', confirmation: '1234567');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<InvalidPinLengthFailure>());
    });

    test('rejects setup when a PIN already exists', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .setupPin(pin: '654321', confirmation: '654321');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<PinAlreadySetFailure>());
    });
  });

  group('unlockWithPin', () {
    test('unlocks with the correct PIN', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithPin('123456');

      expect(result, isA<Ok>());
      expect(c.read(appLockControllerProvider).isUnlocked, isTrue);
    });

    test('rejects an incorrect PIN and counts the attempt', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithPin('000000');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<PinVerificationFailure>());
      final state = c.read(appLockControllerProvider);
      expect(state.status, AppLockStatus.locked);
      expect(state.attempts, 1);
      expect(state.isLockedOut, isFalse);
    });

    test('locks the user out after the free attempts are exhausted', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final notifier = c.read(appLockControllerProvider.notifier);
      for (var i = 0; i < LockoutPolicy.freeAttempts; i++) {
        await notifier.unlockWithPin('000000');
      }
      final result = await notifier.unlockWithPin('000000');

      expect(result, isA<Err>());
      final failure = (result as Err).failure;
      expect(failure, isA<LockedOutFailure>());
      final remaining = (failure as LockedOutFailure).remaining;
      expect(remaining, greaterThan(Duration.zero));
      expect(remaining, lessThanOrEqualTo(const Duration(seconds: 30)));
      final state = c.read(appLockControllerProvider);
      expect(state.isLockedOut, isTrue);
      expect(state.attempts, LockoutPolicy.freeAttempts + 1);
    });

    test('rejects attempts while locked out', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final notifier = c.read(appLockControllerProvider.notifier);
      for (var i = 0; i <= LockoutPolicy.freeAttempts; i++) {
        await notifier.unlockWithPin('000000');
      }
      final result = await notifier.unlockWithPin('123456');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<LockedOutFailure>());
      expect(c.read(appLockControllerProvider).isUnlocked, isFalse);
    });

    test('returns corrupted when stored data is unreadable', () async {
      final c = container();
      addTearDown(c.dispose);
      await storage.write(AppLockStorageKeys.pin, 'garbage');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithPin('123456');

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<CorruptedAuthDataFailure>());
      expect(c.read(appLockControllerProvider).status, AppLockStatus.corrupted);
    });
  });

  group('biometrics', () {
    test('unlocks on biometric success', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      await seedPin('123456');
      await settle(c);
      await enableBiometrics(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithBiometrics();

      expect(result, isA<Ok>());
      expect(c.read(appLockControllerProvider).isUnlocked, isTrue);
    });

    test('fails closed when biometrics are declined', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      await seedPin('123456');
      await settle(c);
      await enableBiometrics(c);
      biometrics.authenticateResult = const Ok(false);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithBiometrics();

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<BiometricFailedFailure>());
      expect(c.read(appLockControllerProvider).isUnlocked, isFalse);
    });

    test('fails closed when biometrics are unavailable', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithBiometrics();

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<BiometricNotAvailableFailure>());
    });

    test('unlock is blocked when biometric unlock is disabled in settings',
        () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      await seedPin('123456');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .unlockWithBiometrics();

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<BiometricDisabledFailure>());
      expect(biometrics.authenticateCalls, 0);
      expect(c.read(appLockControllerProvider).isUnlocked, isFalse);
    });

    test('verifyBiometric is blocked when biometric unlock is disabled',
        () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      await seedPin('123456');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .verifyBiometric();

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<BiometricDisabledFailure>());
      expect(biometrics.authenticateCalls, 0);
    });

    test('verifyBiometric does not unlock', () async {
      final c = container();
      addTearDown(c.dispose);
      biometrics.available = true;
      await seedPin('123456');
      await settle(c);
      await enableBiometrics(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .verifyBiometric();

      expect(result, isA<Ok>());
      expect((result as Ok).value, isTrue);
      expect(c.read(appLockControllerProvider).isUnlocked, isFalse);
    });
  });

  group('changePin', () {
    test('changes the PIN after verifying the current one and keeps data',
        () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await storage.write('protected_note', 'secret-value');
      await settle(c);

      final result = await c.read(appLockControllerProvider.notifier).changePin(
            currentPin: '123456',
            newPin: '789012',
            confirmation: '789012',
          );

      expect(result, isA<Ok>());
      final notifier = c.read(appLockControllerProvider.notifier);
      expect((await notifier.unlockWithPin('789012')), isA<Ok>());
      // The change only replaces the PIN; other stored data is preserved.
      expect(await storage.read('protected_note'), 'secret-value');
    });

    test('rejects a mismatched new PIN', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final result = await c.read(appLockControllerProvider.notifier).changePin(
            currentPin: '123456',
            newPin: '789012',
            confirmation: '999999',
          );

      expect(result, isA<Err>());
      expect((result as Err).failure, isA<PinMismatchFailure>());
    });
  });

  group('lock and reset', () {
    test('lock() re-locks an unlocked app', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);
      await c.read(appLockControllerProvider.notifier).unlockWithPin('123456');
      expect(c.read(appLockControllerProvider).isUnlocked, isTrue);

      c.read(appLockControllerProvider.notifier).lock();
      expect(c.read(appLockControllerProvider).isUnlocked, isFalse);
    });

    test('resetLock clears the PIN and returns to needsSetup', () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await settle(c);

      final result = await c.read(appLockControllerProvider.notifier).resetLock();

      expect(result, isA<Ok>());
      final state = c.read(appLockControllerProvider);
      expect(state.status, AppLockStatus.needsSetup);
      expect(state.attempts, 0);
      expect(await storage.containsKey(AppLockStorageKeys.pin), isFalse);
    });

    test('destructiveReset wipes all local data and returns to needsSetup',
        () async {
      final c = container();
      addTearDown(c.dispose);
      await seedPin('123456');
      await storage.write('protected_note', 'secret-value');
      await settle(c);

      final result = await c
          .read(appLockControllerProvider.notifier)
          .destructiveReset();

      expect(result, isA<Ok>());
      expect(c.read(appLockControllerProvider).status, AppLockStatus.needsSetup);
      expect(await storage.containsKey(AppLockStorageKeys.pin), isFalse);
      expect(await storage.read('protected_note'), isNull);
    });
  });
}