import '../../../core/result/result.dart';
import 'lockout_state.dart';
import 'stored_pin_data.dart';

/// Persistence contract for the local app lock.
///
/// Implementations store data in Keystore-backed secure storage; the plaintext
/// PIN never touches this interface.
abstract interface class AppLockRepository {
  /// Loads the stored PIN material, or `null` when none is set.
  ///
  /// Returns `Err` when stored data exists but cannot be parsed (corrupted).
  Future<Result<StoredPinData?>> loadPin();

  /// Stores [data].
  Future<Result<void>> savePin(StoredPinData data);

  /// Removes the stored PIN material.
  Future<Result<void>> clearPin();

  /// Loads the persisted failed-attempt/lockout state.
  ///
  /// Returns the initial state when nothing is stored.
  Future<Result<LockoutState>> loadLockoutState();

  /// Persists [state].
  Future<Result<void>> saveLockoutState(LockoutState state);

  /// Resets the failed-attempt/lockout state.
  Future<Result<void>> clearLockoutState();
}