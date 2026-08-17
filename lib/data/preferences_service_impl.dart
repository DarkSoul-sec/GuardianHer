import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/preferences_service.dart';

/// Non-sensitive preferences backed by shared_preferences.
class SharedPreferencesService implements PreferencesService {
  const SharedPreferencesService();

  Future<SharedPreferencesAsync> get _instance async => SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) async => (await _instance).getString(key);

  @override
  Future<void> setString(String key, String value) async =>
      (await _instance).setString(key, value);

  @override
  Future<int?> getInt(String key) async => (await _instance).getInt(key);

  @override
  Future<void> setInt(String key, int value) async =>
      (await _instance).setInt(key, value);

  @override
  Future<bool?> getBool(String key) async => (await _instance).getBool(key);

  @override
  Future<void> setBool(String key, bool value) async =>
      (await _instance).setBool(key, value);

  @override
  Future<void> remove(String key) async => (await _instance).remove(key);

  @override
  Future<void> clearAll() async => (await _instance).clear();
}