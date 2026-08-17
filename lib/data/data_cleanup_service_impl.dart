import '../../core/error/failures.dart';
import '../../core/platform/preferences_service.dart';
import '../../core/result/result.dart';
import '../../core/security/data_cleanup_service.dart';
import '../../core/security/secure_storage_service.dart';

/// Clears both secure storage and preferences.
class DataCleanupServiceImpl implements DataCleanupService {
  const DataCleanupServiceImpl({
    required this.secureStorage,
    required this.preferences,
  });

  final SecureStorageService secureStorage;
  final PreferencesService preferences;

  @override
  Future<Result<void>> deleteAllLocalData() async {
    try {
      await secureStorage.clearAll();
      await preferences.clearAll();
      return const Ok<void>(null);
    } on Exception {
      return const Err<void>(
        StorageFailure('Local data could not be fully deleted.'),
      );
    }
  }
}