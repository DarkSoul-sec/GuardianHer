/// Native Android emergency SMS bridge.
///
/// Delegates the critical SMS-sending path to a short-lived Android foreground
/// service that is independent of MainActivity / Flutter-engine lifecycle.
/// Flutter initiates and observes; the native service executes.
///
/// Used exclusively by [EmergencyOrchestrator]. User-initiated SMS continues
/// to use [SmsService] / [UrlLauncherSmsService].
abstract interface class NativeEmergencySmsBridge {
  /// Starts the emergency SMS workflow in the native service.
  ///
  /// Returns immediately; results stream back via [statusUpdates].
  Future<void> startEmergency({
    required String sosEventId,
    required List<EmergencyGuardianData> guardians,
    required String smsBody,
    String? locationUrl,
    int? batteryPercentage,
  });

  /// Best-effort cancellation of any in-progress emergency.
  Future<void> cancelEmergency();

  /// Checks if SEND_SMS permission is currently granted.
  Future<bool> checkSmsPermission();

  /// Requests SEND_SMS permission directly from the OS (not via permission_handler).
  /// Returns true if granted, false if denied.
  Future<bool> requestSmsPermission();

  /// Reads the device battery percentage (0–100), or null if unavailable.
  Future<int?> getBatteryPercentage();

  /// Stream of per-guardian status updates from the native service.
  ///
  /// Events: `{guardianId, status, error?}`
  /// Status values: `sending`, `sent`, `retrying`, `failed`,
  ///                `permission_denied`, `no_sim`.
  Stream<EmergencySmsStatusUpdate> get statusUpdates;

  /// Stream of completion events (all guardians resolved).
  Stream<EmergencySmsCompleteEvent> get completionEvents;
}

/// Minimal guardian data for the native bridge.
class EmergencyGuardianData {
  const EmergencyGuardianData({
    required this.id,
    required this.name,
    required this.phoneNumber,
  });

  final String id;
  final String name;
  final String phoneNumber;

  Map<String, String> toMap() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
      };
}

/// A single status update for a guardian.
class EmergencySmsStatusUpdate {
  const EmergencySmsStatusUpdate({
    required this.guardianId,
    required this.status,
    this.error,
  });

  final String guardianId;
  final String status;
  final String? error;
}

/// Fired when the native service has resolved all guardians.
class EmergencySmsCompleteEvent {
  const EmergencySmsCompleteEvent({
    required this.sosEventId,
    required this.totalSent,
    required this.totalFailed,
  });

  final String sosEventId;
  final int totalSent;
  final int totalFailed;
}
