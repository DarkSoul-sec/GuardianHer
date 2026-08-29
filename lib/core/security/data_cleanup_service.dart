import '../result/result.dart';

/// Removes all locally stored application data.
///
/// Used by the "Delete local data" privacy action. Clears both secure storage
/// (contacts, history) and preferences (settings), returning the app to a
/// first-launch state.
abstract interface class DataCleanupService {
  Future<Result<void>> deleteAllLocalData();
}