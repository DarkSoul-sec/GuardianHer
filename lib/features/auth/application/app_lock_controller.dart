import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failures.dart';
import '../../../core/platform/biometric_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../settings/application/settings_providers.dart';
import '../domain/app_lock_failures.dart';
import '../domain/app_lock_repository.dart';
import '../domain/app_lock_status.dart';
import '../domain/lockout_state.dart';
import 'app_lock_providers.dart';
import 'app_lock_state.dart';
import 'lockout_policy.dart';
import 'pin_hasher.dart';

/// Manages the local app lock state outside of widgets.
///
/// The controller owns initialization (first-launch detection), PIN setup,
/// PIN/biometric unlock, failed-attempt lockout, and the reset path. All
/// platform interactions flow through injected [AppLockRepository] and
/// [BiometricService] abstractions so the logic is fully unit-testable.
class AppLockController extends Notifier<AppLockState> {
  AppLockRepository get _repository => ref.read(appLockRepositoryProvider);
  BiometricService get _biometrics => ref.read(biometricServiceProvider);
  PinHasher get _hasher => ref.read(pinHasherProvider);

  /// Whether biometric unlock is enabled in security settings. This is the
  /// authoritative gate for all biometric use: the UI is not the only
  /// enforcement point.
  bool get _biometricEnabled =>
      ref.read(securitySettingsControllerProvider).biometricEnabled;

  Future<void>? _initializing;

  @override
  AppLockState build() {
    initialize();
    return const AppLockState(status: AppLockStatus.unknown);
  }

  /// Resolves the lock state from persisted data. Idempotent.
  Future<void> initialize() => _initializing ??= _doInitialize();

  /// Forces a fresh resolution (e.g. after local data was deleted).
  Future<void> reinitialize() async {
    _initializing = null;
    await initialize();
  }

  Future<void> _doInitialize() async {
    var biometricsAvailable = false;
    try {
      biometricsAvailable = await _biometrics.isAvailable();
    } on Exception {
      biometricsAvailable = false;
    }

    switch (await _repository.loadPin()) {
      case Err():
        state = AppLockState(
          status: AppLockStatus.corrupted,
          biometricsAvailable: biometricsAvailable,
        );
      case Ok(:final value):
        var lockout = const LockoutState.initial();
        final lockoutResult = await _repository.loadLockoutState();
        if (lockoutResult is Ok<LockoutState>) {
          lockout = lockoutResult.value;
        }
        final remaining = _remainingDelay(lockout);
        state = AppLockState(
          status: value == null
              ? AppLockStatus.needsSetup
              : AppLockStatus.locked,
          biometricsAvailable: biometricsAvailable,
          attempts: lockout.failedAttempts,
          isLockedOut: remaining > Duration.zero,
          lockoutRemaining: remaining,
        );
    }
  }

  /// Creates the app lock PIN. Requires [pin] to match [confirmation] and to
  /// satisfy [PinPolicy].
  Future<Result<void>> setupPin({
    required String pin,
    required String confirmation,
  }) async {
    if (pin != confirmation) {
      return const Err(PinMismatchFailure());
    }
    if (!PinPolicy.isValid(pin)) {
      return const Err(InvalidPinLengthFailure());
    }
    final current = state.status;
    if (current != AppLockStatus.needsSetup &&
        current != AppLockStatus.corrupted) {
      return const Err(PinAlreadySetFailure());
    }
    try {
      final stored = await _hasher.hashPin(pin);
      final saved = await _repository.savePin(stored);
      if (saved is Err<void>) return Err(saved.failure);
      await _repository.clearLockoutState();
      state = state.copyWith(
        status: AppLockStatus.unlocked,
        attempts: 0,
        isLockedOut: false,
        lockoutRemaining: Duration.zero,
      );
      return const Ok<void>(null);
    } on Exception {
      return const Err<void>(UnexpectedFailure('The PIN could not be saved.'));
    }
  }

  /// Unlocks the app by verifying [pin] against the stored hash.
  Future<Result<void>> unlockWithPin(String pin) async {
    if (!PinPolicy.isValid(pin)) {
      return const Err(InvalidPinLengthFailure());
    }

    final lockoutResult = await _repository.loadLockoutState();
    final lockout = switch (lockoutResult) {
      Ok(:final value) => value,
      _ => const LockoutState.initial(),
    };
    final remaining = _remainingDelay(lockout);
    if (remaining > Duration.zero) {
      state = state.copyWith(
        attempts: lockout.failedAttempts,
        isLockedOut: true,
        lockoutRemaining: remaining,
      );
      return Err(LockedOutFailure(remaining));
    }

    switch (await _repository.loadPin()) {
      case Err():
        state = state.copyWith(status: AppLockStatus.corrupted);
        return const Err(CorruptedAuthDataFailure());
      case Ok(:final value):
        final stored = value;
        if (stored == null) {
          state = state.copyWith(status: AppLockStatus.needsSetup);
          return const Err(
            CorruptedAuthDataFailure(message: 'No PIN data is stored.'),
          );
        }
        final verified = await _hasher.verifyPin(pin, stored);
        if (verified) {
          await _repository.clearLockoutState();
          state = state.copyWith(
            status: AppLockStatus.unlocked,
            attempts: 0,
            isLockedOut: false,
            lockoutRemaining: Duration.zero,
          );
          return const Ok<void>(null);
        }
        final attempts = lockout.failedAttempts + 1;
        final delay = LockoutPolicy.delayForAttempt(attempts);
        final until = delay > Duration.zero
            ? DateTime.now().add(delay)
            : null;
        await _repository.saveLockoutState(
          LockoutState(failedAttempts: attempts, lockoutUntil: until),
        );
        state = state.copyWith(
          attempts: attempts,
          isLockedOut: delay > Duration.zero,
          lockoutRemaining: delay,
        );
        return delay > Duration.zero
            ? Err(LockedOutFailure(delay))
            : const Err(PinVerificationFailure());
    }
  }

  /// Unlocks the app via biometrics when enabled in settings, available on the
  /// device, and the user consents.
  Future<Result<void>> unlockWithBiometrics() async {
    if (!state.biometricsAvailable) {
      return const Err(BiometricNotAvailableFailure());
    }
    if (!_biometricEnabled) {
      return const Err(BiometricDisabledFailure());
    }
    final result = await _biometrics.authenticate(reason: 'Unlock GuardianHer');
    if (result is Ok<bool> && result.value) {
      await _repository.clearLockoutState();
      state = state.copyWith(
        status: AppLockStatus.unlocked,
        attempts: 0,
        isLockedOut: false,
        lockoutRemaining: Duration.zero,
      );
      return const Ok<void>(null);
    }
    if (result is Err<bool>) return Err(result.failure);
    return const Err(BiometricFailedFailure());
  }

  /// Prompts for biometrics without unlocking (used to gate destructive
  /// actions such as resetting the app lock).
  ///
  /// Policy: a biometric prompt is only offered when the user has enabled
  /// biometric unlock in security settings AND the device supports it. When
  /// biometrics are disabled this fails with [BiometricDisabledFailure] and
  /// never contacts the platform authenticator.
  Future<Result<bool>> verifyBiometric({
    String reason = 'Verify your identity',
  }) async {
    if (!state.biometricsAvailable) {
      return const Err(BiometricNotAvailableFailure());
    }
    if (!_biometricEnabled) {
      return const Err(BiometricDisabledFailure());
    }
    return _biometrics.authenticate(reason: reason);
  }

  /// Replaces the existing PIN. [currentPin] must be valid first.
  Future<Result<void>> changePin({
    required String currentPin,
    required String newPin,
    required String confirmation,
  }) async {
    final verified = await unlockWithPin(currentPin);
    if (verified is Err) return verified;
    if (newPin != confirmation) {
      return const Err(PinMismatchFailure());
    }
    if (!PinPolicy.isValid(newPin)) {
      return const Err(InvalidPinLengthFailure());
    }
    try {
      final stored = await _hasher.hashPin(newPin);
      final saved = await _repository.savePin(stored);
      if (saved is Err<void>) return Err(saved.failure);
      return const Ok<void>(null);
    } on Exception {
      return const Err<void>(UnexpectedFailure('The new PIN could not be saved.'));
    }
  }

  /// Immediately locks the app.
  void lock() {
    state = state.copyWith(status: AppLockStatus.locked);
  }

  /// Recovery path: clears PIN material and returns the app to [AppLockStatus.needsSetup].
  ///
  /// This is a SOFT reset that preserves all other local data. Callers MUST
  /// verify the user's identity first (a successful PIN check or a biometric
  /// verification while biometric unlock is enabled) before invoking. Use
  /// [destructiveReset] instead when identity cannot be verified.
  Future<Result<void>> resetLock() async {
    try {
      final cleared = await _repository.clearPin();
      if (cleared is Err<void>) return Err(cleared.failure);
      await _repository.clearLockoutState();
      state = state.copyWith(
        status: AppLockStatus.needsSetup,
        attempts: 0,
        isLockedOut: false,
        lockoutRemaining: Duration.zero,
      );
      return const Ok<void>(null);
    } on Exception {
      return const Err<void>(UnexpectedFailure('The app lock could not be reset.'));
    }
  }

  /// Destructive recovery path for when the user cannot verify their identity.
  ///
  /// Permanently deletes ALL locally stored data (PIN material, app settings,
  /// contacts, history) via [DataCleanupService], then re-resolves the lock so
  /// the app returns to first-launch setup. The user is required to create a
  /// new PIN; the deleted data is never recovered. There is no mechanism to
  /// regain access to protected data without identity verification.
  Future<Result<void>> destructiveReset() async {
    try {
      final cleared = await ref
          .read(dataCleanupServiceProvider)
          .deleteAllLocalData();
      if (cleared is Err<void>) return Err(cleared.failure);
      // Preferences were wiped; drop any in-memory security settings so the
      // biometric/lock-delay state returns to fresh defaults too.
      ref.invalidate(securitySettingsControllerProvider);
      await reinitialize();
      return const Ok<void>(null);
    } on Exception {
      return const Err<void>(
        UnexpectedFailure('The local data could not be deleted.'),
      );
    }
  }

  Duration _remainingDelay(LockoutState lockout) {
    final until = lockout.lockoutUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}