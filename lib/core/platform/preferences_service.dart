/// Abstraction over lightweight, non-sensitive preferences storage.
///
/// Backed by shared_preferences. Never stores sensitive data (tokens, PIN
/// material, contact information); those belong in [SecureStorageService].
abstract interface class PreferencesService {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);

  /// Removes a single value.
  Future<void> remove(String key);

  /// Removes every preference stored by the app.
  Future<void> clearAll();
}