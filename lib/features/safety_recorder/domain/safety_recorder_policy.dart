/// Centralized policy constants for the Safety Recorder.
///
/// All magic numbers live here — not scattered across controllers or
/// repositories. The defaults match the Phase E spec; tests can override
/// individual values via providers.
abstract final class SafetyRecorderPolicy {
  SafetyRecorderPolicy._();

  /// Maximum number of events kept in the rolling pre-event buffer.
  static const int maxBufferSize = 500;

  /// How far back (in minutes) the rolling buffer retains events.
  static const int preEventWindowMinutes = 10;

  /// Maximum number of completed incidents retained on disk.
  static const int maxIncidents = 20;

  /// SharedPreferences key prefix for persisted incidents.
  static const String storageKeyPrefix = 'safety_recorder_incidents_';

  /// SharedPreferences key for the storage format version.
  static const String storageVersionKey = 'safety_recorder_version';

  /// Current storage format version.
  static const int currentStorageVersion = 1;
}
