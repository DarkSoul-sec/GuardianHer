import 'package:flutter/foundation.dart';

import '../../../features/journey/domain/vehicle_info.dart';
import '../../journey/domain/safety_recorder_events.dart';
import 'incident_integrity.dart';

/// Lifecycle status of a safety incident.
enum SafetyIncidentStatus {
  /// The incident is actively recording events.
  recording,

  /// SOS is active; the buffer is frozen for post-event retention.
  frozen,

  /// The incident is complete and persisted.
  completed,
}

/// A completed or in-progress safety incident.
///
/// An incident groups events from a single safety session (SOS, journey, etc.)
/// with a tamper-evident hash chain for integrity verification.
@immutable
class SafetyIncident {
  const SafetyIncident({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.events,
    required this.hashes,
    required this.genesisHash,
    this.endedAt,
    this.vehicleType,
    this.hasVehicleRegistration = false,
  });

  /// Unique incident id (32 hex chars, same format as session ids).
  final String id;

  final SafetyIncidentStatus status;

  /// When the incident was created (SOS activation or manual start).
  final DateTime createdAt;

  /// When the incident was finalized (SOS completion or manual end).
  final DateTime? endedAt;

  /// Ordered list of recorded events in this incident.
  final List<RecordedSafetyEvent> events;

  /// Hash chain: hashes[i] corresponds to events[i].
  final List<String> hashes;

  /// The genesis hash that starts the chain.
  final String genesisHash;

  /// Vehicle type if a vehicle was attached during this incident.
  final VehicleType? vehicleType;

  /// Whether a vehicle registration was present (never the number itself).
  final bool hasVehicleRegistration;

  /// Whether this incident is still actively recording.
  bool get isActive =>
      status == SafetyIncidentStatus.recording ||
      status == SafetyIncidentStatus.frozen;

  /// Duration of the incident from start to end (or now if still active).
  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(createdAt);
  }

  /// Whether the integrity chain can be verified.
  bool get canVerifyIntegrity =>
      status == SafetyIncidentStatus.completed && events.isNotEmpty;

  /// Verify the integrity of the event chain.
  bool verifyIntegrity() {
    if (!canVerifyIntegrity) return false;
    return verifyIncidentIntegrity(
      genesisHash: genesisHash,
      events: events,
      hashes: hashes,
    );
  }

  SafetyIncident copyWith({
    String? id,
    SafetyIncidentStatus? status,
    DateTime? createdAt,
    DateTime? Function()? endedAt,
    List<RecordedSafetyEvent>? events,
    List<String>? hashes,
    String? genesisHash,
    VehicleType? vehicleType,
    bool? hasVehicleRegistration,
  }) {
    return SafetyIncident(
      id: id ?? this.id,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt != null ? endedAt() : this.endedAt,
      events: events ?? this.events,
      hashes: hashes ?? this.hashes,
      genesisHash: genesisHash ?? this.genesisHash,
      vehicleType: vehicleType ?? this.vehicleType,
      hasVehicleRegistration:
          hasVehicleRegistration ?? this.hasVehicleRegistration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SafetyIncident && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SafetyIncident(${id.substring(0, 8)}…, ${status.name}, '
      '${events.length} events)';
}
