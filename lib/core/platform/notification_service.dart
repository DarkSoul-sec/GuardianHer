import '../result/result.dart';

/// Abstraction over local notification capability for the SOS workflow.
///
/// The SOS notification is a secondary, best-effort capability: a failure or a
/// denied permission must never affect the SOS state machine, only the UI
/// status report. Notification content stays generic and privacy-preserving;
/// the implementation owns the Android channel and notification id.
abstract interface class NotificationService {
  /// Whether the app currently has permission to show notifications.
  ///
  /// On Android versions before 13 this is `true`.
  Future<Result<bool>> isPermissionGranted();

  /// Requests notification permission from the OS (in context, never at
  /// application startup).
  Future<Result<void>> requestPermission();

  /// Shows or updates the ongoing "SOS ACTIVE" notification.
  Future<Result<void>> showSosActive();

  /// Updates the notification to reflect that SOS is stopping.
  Future<Result<void>> showSosStopping();

  /// Removes the SOS notification. Idempotent.
  Future<Result<void>> cancelSos();
}
