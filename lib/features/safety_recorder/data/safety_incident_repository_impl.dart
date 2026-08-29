import '../../../core/error/failures.dart';
import '../../../core/platform/preferences_service.dart';
import '../../../core/result/result.dart';
import '../domain/safety_incident.dart';
import '../domain/safety_recorder_policy.dart';
import 'safety_event_serializer.dart';
import 'safety_incident_repository.dart';

/// SharedPreferences-backed persistence for safety incidents.
///
/// Stores a versioned JSON blob containing the incident list. The max
/// incident count is enforced by the policy — the oldest incident is
/// evicted when the limit is exceeded.
class SafetyIncidentRepositoryImpl implements SafetyIncidentRepository {
  const SafetyIncidentRepositoryImpl({
    required PreferencesService this._preferences,
    String? keyPrefix,
  }) : _keyPrefix = keyPrefix ?? SafetyRecorderPolicy.storageKeyPrefix;

  final PreferencesService _preferences;
  final String _keyPrefix;

  String get _listKey => '${_keyPrefix}list';
  String get _versionKey => SafetyRecorderPolicy.storageVersionKey;

  /// Loads all persisted incidents, newest first.
  @override
  Future<Result<List<SafetyIncident>>> loadAll() async {
    try {
      await _ensureVersion();
      final json = await _preferences.getString(_listKey);
      if (json == null || json.isEmpty) {
        return const Ok([]);
      }
      final incidents = SafetyEventSerializer.decodeIncidents(json);
      return Ok(incidents);
    } on Exception {
      return const Err(StorageFailure(
        'Could not load safety incidents.',
      ));
    }
  }

  /// Saves a completed incident (upsert by id).
  ///
  /// If the incident count exceeds the policy limit, the oldest incident
  /// is evicted.
  @override
  Future<Result<void>> save(SafetyIncident incident) async {
    try {
      await _ensureVersion();
      final existing = await _loadRaw();
      final updated = [...existing];
      final index = updated.indexWhere((i) => i.id == incident.id);
      if (index >= 0) {
        updated[index] = incident;
      } else {
        updated.add(incident);
      }
      // Enforce max incident limit (keep newest).
      while (updated.length > SafetyRecorderPolicy.maxIncidents) {
        updated.removeAt(0);
      }
      await _saveRaw(updated);
      return const Ok(null);
    } on Exception {
      return const Err(StorageFailure(
        'Could not save safety incident.',
      ));
    }
  }

  /// Deletes an incident by id.
  @override
  Future<Result<void>> delete(String id) async {
    try {
      final existing = await _loadRaw();
      final updated = existing.where((i) => i.id != id).toList();
      await _saveRaw(updated);
      return const Ok(null);
    } on Exception {
      return const Err(StorageFailure(
        'Could not delete safety incident.',
      ));
    }
  }

  /// Deletes all incidents (privacy action).
  @override
  Future<Result<void>> clearAll() async {
    try {
      await _preferences.remove(_listKey);
      return const Ok(null);
    } on Exception {
      return const Err(StorageFailure(
        'Could not clear safety incidents.',
      ));
    }
  }

  Future<void> _ensureVersion() async {
    final current = await _preferences.getInt(_versionKey);
    if (current == null || current < SafetyRecorderPolicy.currentStorageVersion) {
      await _preferences.setInt(
        _versionKey,
        SafetyRecorderPolicy.currentStorageVersion,
      );
    }
  }

  Future<List<SafetyIncident>> _loadRaw() async {
    final json = await _preferences.getString(_listKey);
    if (json == null || json.isEmpty) return [];
    return SafetyEventSerializer.decodeIncidents(json);
  }

  Future<void> _saveRaw(List<SafetyIncident> incidents) async {
    final json = SafetyEventSerializer.encodeIncidents(incidents);
    await _preferences.setString(_listKey, json);
  }
}
