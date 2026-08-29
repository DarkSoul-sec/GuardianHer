import 'dart:convert';

import '../domain/safety_incident.dart';
import '../../../features/journey/domain/safety_recorder_events.dart';
import '../../../features/journey/domain/vehicle_info.dart';

/// JSON serialization for [SafetyIncident] and [RecordedSafetyEvent].
///
/// The format is versioned: a top-level `{"version":1, "incidents":[...]}`.
/// Unknown fields are ignored for forward compatibility; missing fields
/// decode to safe defaults.
abstract final class SafetyEventSerializer {
  SafetyEventSerializer._();

  /// Serializes a list of incidents to a JSON string.
  static String encodeIncidents(List<SafetyIncident> incidents) {
    return jsonEncode({
      'version': 1,
      'incidents': incidents.map(_encodeIncident).toList(),
    });
  }

  /// Decodes a JSON string into a list of incidents.
  ///
  /// Returns an empty list on any parse error (corrupt data is not fatal).
  static List<SafetyIncident> decodeIncidents(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final version = map['version'] as int? ?? 0;
      if (version > 1) return [];
      final list = map['incidents'] as List<dynamic>? ?? [];
      return list
          .map((e) => _decodeIncident(e as Map<String, dynamic>))
          .whereType<SafetyIncident>()
          .toList();
    } on Exception {
      return [];
    }
  }

  static Map<String, dynamic> _encodeIncident(SafetyIncident incident) {
    return {
      'id': incident.id,
      'status': incident.status.name,
      'createdAt': incident.createdAt.toIso8601String(),
      'endedAt': incident.endedAt?.toIso8601String(),
      'events': incident.events.map(_encodeEvent).toList(),
      'hashes': incident.hashes,
      'genesisHash': incident.genesisHash,
      'vehicleType': incident.vehicleType?.name,
      'hasVehicleRegistration': incident.hasVehicleRegistration,
    };
  }

  static Map<String, dynamic> _encodeEvent(RecordedSafetyEvent event) {
    return {
      'eventId': event.eventId,
      'eventType': event.eventType.name,
      'occurredAt': event.occurredAt.toIso8601String(),
      'sessionId': event.sessionId,
      'metadata': event.metadata,
    };
  }

  static SafetyIncident? _decodeIncident(Map<String, dynamic> map) {
    try {
      final id = map['id'] as String?;
      if (id == null || id.isEmpty) return null;

      final statusName = map['status'] as String? ?? 'completed';
      final status = SafetyIncidentStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => SafetyIncidentStatus.completed,
      );

      final createdAt = DateTime.tryParse(map['createdAt'] as String? ?? '');
      if (createdAt == null) return null;

      final endedAtStr = map['endedAt'] as String?;
      final endedAt = endedAtStr != null
          ? DateTime.tryParse(endedAtStr)
          : null;

      final eventsList = map['events'] as List<dynamic>? ?? [];
      final events = eventsList
          .map((e) => _decodeEvent(e as Map<String, dynamic>))
          .whereType<RecordedSafetyEvent>()
          .toList();

      final hashes = (map['hashes'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList();

      final genesisHash = map['genesisHash'] as String? ?? '';

      final vehicleTypeName = map['vehicleType'] as String?;
      final vehicleType = vehicleTypeName != null
          ? VehicleType.values.firstWhere(
              (v) => v.name == vehicleTypeName,
              orElse: () => VehicleType.other,
            )
          : null;

      final hasVehicleRegistration =
          map['hasVehicleRegistration'] as bool? ?? false;

      return SafetyIncident(
        id: id,
        status: status,
        createdAt: createdAt,
        endedAt: endedAt,
        events: events,
        hashes: hashes,
        genesisHash: genesisHash,
        vehicleType: vehicleType,
        hasVehicleRegistration: hasVehicleRegistration,
      );
    } on Exception {
      return null;
    }
  }

  static RecordedSafetyEvent? _decodeEvent(Map<String, dynamic> map) {
    try {
      final eventId = map['eventId'] as String?;
      if (eventId == null || eventId.isEmpty) return null;

      final typeName = map['eventType'] as String?;
      if (typeName == null) return null;
      final eventType = SafetyEventType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => SafetyEventType.sessionStarted,
      );

      final occurredAt = DateTime.tryParse(map['occurredAt'] as String? ?? '');
      if (occurredAt == null) return null;

      final sessionId = map['sessionId'] as String? ?? '';

      final metadata = (map['metadata'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String));

      return RecordedSafetyEvent(
        eventId: eventId,
        eventType: eventType,
        occurredAt: occurredAt,
        sessionId: sessionId,
        metadata: metadata,
      );
    } on Exception {
      return null;
    }
  }
}
