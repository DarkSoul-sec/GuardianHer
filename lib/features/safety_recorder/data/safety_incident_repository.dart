import '../../../core/result/result.dart';
import '../domain/safety_incident.dart';

/// Abstract interface for persisting safety incidents.
///
/// The recorder writes incidents here on completion. The UI reads them
/// for the timeline. No coordinates, no PII — only the incident model.
abstract interface class SafetyIncidentRepository {
  /// Loads all completed incidents, newest first.
  Future<Result<List<SafetyIncident>>> loadAll();

  /// Saves a completed incident (upsert by id).
  Future<Result<void>> save(SafetyIncident incident);

  /// Deletes an incident by id.
  Future<Result<void>> delete(String id);

  /// Deletes all incidents (privacy action).
  Future<Result<void>> clearAll();
}
