/// Seam for the fake-call alert (ringtone + vibration loop).
///
/// Implemented natively over `guardianher/fake_call` using the system default
/// ringtone and the vibrator — no audio files, no downloads, no microphone.
/// Both methods are idempotent and must never throw.
abstract interface class FakeCallAlertService {
  /// Starts looping the system ringtone; vibrates too when [vibrate] is true.
  Future<void> startAlert({required bool vibrate});

  /// Stops ringtone and vibration immediately. Idempotent.
  Future<void> stopAlert();
}

/// Seam for the background fallback notification.
///
/// When the scheduled delay elapses, a high-importance notification is posted
/// so a backgrounded user is still alerted; tapping it opens the incoming
/// screen. Uses the shared local-notifications plugin (same channel pattern
/// as check-in reminders) — no second plugin, no full-screen intent, no
/// overlay, no new permissions.
abstract interface class FakeCallNotifier {
  /// Schedules the "Incoming call" notification for [fireAt].
  Future<void> scheduleIncomingCall({
    required String callerName,
    required DateTime fireAt,
  });

  /// Posts the "Incoming call" notification immediately.
  Future<void> showIncomingCallNow({required String callerName});

  /// Removes the notification. Idempotent.
  Future<void> cancelIncomingCall();
}
