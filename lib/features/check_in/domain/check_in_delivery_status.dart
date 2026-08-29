/// Outcome of one scheduled Safety Check-In execution.
///
/// The states deliberately separate WHAT HAPPENED LOCALLY from WHAT THE USER
/// STILL HAS TO DO, because delivery is user-mediated (Phase 3G): opening a
/// composer is never a delivery. The UI maps these onto distinct labels —
/// "Location captured", "Waiting for you to send", "Location unavailable" —
/// and nothing ever claims a message was sent unless it truly was.
enum CheckInExecutionStatus {
  /// Nothing ran: feature disabled in persisted config.
  disabled,

  /// Nothing ran: the user picked no recipients.
  noRecipients,

  /// SOS took priority; the check-in was skipped and rescheduled.
  skippedForSos,

  /// Location captured fresh; message composed and handed to the sender.
  locationCaptured,

  /// Only a labeled last-known fix was available; message marks it stale.
  staleOnly,

  /// No fix at all; message says so explicitly.
  locationUnavailable,

  /// Location permission was revoked since the feature was enabled.
  permissionDenied,

  /// Device location services (GPS/network switch) were off at fire time.
  servicesDisabled,

  /// The one-shot location capture timed out.
  timeout,

  /// Scheduling the next execution failed (or the platform does not support
  /// it); the cadence cannot continue until re-enabled.
  schedulerFailed,

  /// The platform refuses location access from the background
  /// (Android 10+ without ACCESS_BACKGROUND_LOCATION).
  locationRestrictedInBackground,

  /// Sender could not open any channel.
  communicationFailed,

  /// Some recipients got channels, some did not.
  partialDelivery,
}

extension CheckInExecutionStatusLabel on CheckInExecutionStatus {
  /// Short user-facing label. Never implies a message was delivered.
  String get label => switch (this) {
        CheckInExecutionStatus.disabled => 'Check-in is off',
        CheckInExecutionStatus.noRecipients => 'No recipients selected',
        CheckInExecutionStatus.skippedForSos => 'Skipped: emergency active',
        CheckInExecutionStatus.locationCaptured =>
          'Location captured — waiting for you to send',
        CheckInExecutionStatus.staleOnly =>
          'Last known location attached — waiting for you to send',
        CheckInExecutionStatus.locationUnavailable =>
          'Location unavailable — waiting for you to send',
        CheckInExecutionStatus.permissionDenied =>
          'Location permission denied — open GuardianHer to fix',
        CheckInExecutionStatus.servicesDisabled =>
          'Location services are off — waiting for you to send',
        CheckInExecutionStatus.timeout =>
          'Location timed out — waiting for you to send',
        CheckInExecutionStatus.schedulerFailed =>
          'Could not schedule the next check-in',
        CheckInExecutionStatus.locationRestrictedInBackground =>
          'Background location restricted — open GuardianHer to check in',
        CheckInExecutionStatus.communicationFailed =>
          'Could not open any messaging channel',
        CheckInExecutionStatus.partialDelivery =>
          'Opened for some recipients only',
      };
}
