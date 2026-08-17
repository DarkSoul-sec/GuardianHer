import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../../../core/security/secure_storage_service.dart';
import '../domain/app_lock_failures.dart';
import '../domain/app_lock_repository.dart';
import '../domain/credential_policy.dart';
import '../domain/lockout_state.dart';
import '../domain/stored_pin_data.dart';

/// Keys used to persist app-lock material in secure storage.
abstract final class AppLockStorageKeys {
  AppLockStorageKeys._();

  static const pin = 'app_lock_pin';
  static const lockout = 'app_lock_lockout';
}

/// Stores app-lock material in Keystore-backed secure storage.
///
/// Only the derived representation (salt + hash + iterations) is persisted.
class SecureStorageAppLockRepository implements AppLockRepository {
  const SecureStorageAppLockRepository({
    required this.storage,
    this.policy = const CredentialPolicy(),
  });

  final SecureStorageService storage;

  /// Validation rules applied to stored credentials on load.
  final CredentialPolicy policy;

  @override
  Future<Result<StoredPinData?>> loadPin() async {
    try {
      final raw = await storage.read(AppLockStorageKeys.pin);
      if (raw == null) return const Ok(null);
      final stored = StoredPinData.tryDecode(raw, policy: policy);
      return stored == null
          ? const Err(CorruptedAuthDataFailure())
          : Ok(stored);
    } on Exception {
      return const Err(StorageFailure('The stored PIN data could not be read.'));
    }
  }

  @override
  Future<Result<void>> savePin(StoredPinData data) async {
    try {
      await storage.write(AppLockStorageKeys.pin, data.encode());
      return const Ok<void>(null);
    } on Exception {
      return const Err(StorageFailure('The PIN could not be stored.'));
    }
  }

  @override
  Future<Result<void>> clearPin() async {
    try {
      await storage.delete(AppLockStorageKeys.pin);
      return const Ok<void>(null);
    } on Exception {
      return const Err(StorageFailure('The stored PIN could not be cleared.'));
    }
  }

  @override
  Future<Result<LockoutState>> loadLockoutState() async {
    try {
      final raw = await storage.read(AppLockStorageKeys.lockout);
      if (raw == null) return const Ok(LockoutState.initial());
      return Ok(LockoutState.tryDecode(raw) ?? const LockoutState.initial());
    } on Exception {
      return const Err(StorageFailure('The lockout state could not be read.'));
    }
  }

  @override
  Future<Result<void>> saveLockoutState(LockoutState state) async {
    try {
      await storage.write(AppLockStorageKeys.lockout, state.encode());
      return const Ok<void>(null);
    } on Exception {
      return const Err(StorageFailure('The lockout state could not be stored.'));
    }
  }

  @override
  Future<Result<void>> clearLockoutState() async {
    try {
      await storage.delete(AppLockStorageKeys.lockout);
      return const Ok<void>(null);
    } on Exception {
      return const Err(StorageFailure('The lockout state could not be cleared.'));
    }
  }
}