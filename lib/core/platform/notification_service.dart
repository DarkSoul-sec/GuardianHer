import '../result/result.dart';

/// Abstraction over local notification capability.
///
/// Android 13+ requires a runtime permission for notifications; the
/// implementation will request it through this interface when needed.
abstract interface class NotificationService {
  /// Whether the app currently has permission to show notifications.
  Future<Result<bool>> isPermissionGranted();

  /// Requests notification permission from the OS.
  Future<Result<void>> requestPermission();
}