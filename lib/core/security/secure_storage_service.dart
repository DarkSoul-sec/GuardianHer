/// Abstraction over Keystore-backed secure storage.
///
/// Used for sensitive data such as trusted contacts and emergency history.
/// Implementations are injected in later phases; presentation code
/// never touches the storage plugin directly.
abstract interface class SecureStorageService {
  /// Reads the value stored under [key], or `null` when absent.
  Future<String?> read(String key);

  /// Stores [value] under [key], overwriting any existing value.
  Future<void> write(String key, String value);

  /// Removes the value stored under [key].
  Future<void> delete(String key);

  /// Whether a value exists under [key].
  Future<bool> containsKey(String key);

  /// Removes every value stored by the app.
  Future<void> clearAll();
}