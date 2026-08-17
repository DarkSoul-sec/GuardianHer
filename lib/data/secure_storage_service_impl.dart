import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/security/secure_storage_service.dart';

/// Keystore-backed secure storage backed by flutter_secure_storage.
class FlutterSecureStorageService implements SecureStorageService {
  const FlutterSecureStorageService({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) => storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => storage.containsKey(key: key);

  @override
  Future<void> clearAll() => storage.deleteAll();
}