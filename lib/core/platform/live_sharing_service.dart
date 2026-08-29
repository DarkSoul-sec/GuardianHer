/// Native Android live sharing service bridge.
///
/// Delegates continuous location sharing via SMS to a foreground service
/// that survives app backgrounding. Uses SMS as the relay — no server needed.
abstract interface class LiveSharingService {
  /// Starts live sharing to [contacts] (digits-only E.164 numbers).
  ///
  /// [intervalSeconds] — update interval (default 30s).
  /// Returns true if service started successfully.
  Future<bool> start({
    required List<String> contacts,
    int intervalSeconds = 30,
  });

  /// Stops live sharing.
  Future<void> stop();

  /// Forces an immediate location update.
  Future<void> forceUpdate();
}