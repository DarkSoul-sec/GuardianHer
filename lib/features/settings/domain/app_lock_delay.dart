/// How quickly the app must be re-locked after it leaves the foreground.
enum AppLockDelay {
  immediate('immediate', Duration.zero, 'Immediately'),
  oneMinute('oneMinute', Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes('fiveMinutes', Duration(minutes: 5), 'After 5 minutes'),
  never('never', null, 'Never');

  const AppLockDelay(this.storageValue, this.duration, this.label);

  /// Persisted representation.
  final String storageValue;

  /// Minimum background time that triggers a lock, or `null` for never.
  final Duration? duration;

  /// Human-readable label for the UI.
  final String label;

  static AppLockDelay fromStorage(String? value) {
    return values.firstWhere(
      (delay) => delay.storageValue == value,
      orElse: () => AppLockDelay.immediate,
    );
  }
}