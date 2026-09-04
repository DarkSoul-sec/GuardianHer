/// Interface for reading battery level and state.
abstract interface class BatteryService {
  /// Returns battery level as percentage (0-100), or null if unavailable.
  Future<int?> getBatteryLevel();

  /// Returns whether device is currently charging.
  Future<bool?> isCharging();
}