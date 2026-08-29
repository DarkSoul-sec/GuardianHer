import 'dart:math';

import 'package:flutter/foundation.dart';

import 'vehicle_info.dart';

/// Generates a cryptographically random event id (32 lowercase hex chars).

/// Generates a cryptographically random event id (32 lowercase hex chars).
String generateRecorderEventId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// High-level category for safety events.
enum SafetyEventCategory {
  session,
  journey,
  sos,
  location,
  communication,
  checkIn,
}

/// Specific type of safety event.
enum SafetyEventType {
  sessionStarted,
  sessionCompleted,
  sessionExpired,
  vehicleAttached,
  journeyStarted,
  journeyEnded,
  sosActivated,
  sosCancellationStarted,
  sosCompleted,
  locationCaptureStarted,
  locationCaptured,
  locationUnavailable,
  locationTimeout,
  locationPermissionDenied,
  locationServicesDisabled,
  locationUpdated,
  communicationAttempted,
  communicationFailed,
  communicationHandedOff,
  shakeDetected,
  checkInStarted,
  checkInCompleted,
}

/// Maps an event type to its category.
SafetyEventCategory categoryForEventType(SafetyEventType type) {
  return switch (type) {
    SafetyEventType.sessionStarted ||
    SafetyEventType.sessionCompleted ||
    SafetyEventType.sessionExpired ||
    SafetyEventType.vehicleAttached =>
      SafetyEventCategory.session,
    SafetyEventType.journeyStarted ||
    SafetyEventType.journeyEnded =>
      SafetyEventCategory.journey,
    SafetyEventType.sosActivated ||
    SafetyEventType.sosCancellationStarted ||
    SafetyEventType.sosCompleted ||
    SafetyEventType.shakeDetected =>
      SafetyEventCategory.sos,
    SafetyEventType.locationCaptureStarted ||
    SafetyEventType.locationCaptured ||
    SafetyEventType.locationUnavailable ||
    SafetyEventType.locationTimeout ||
    SafetyEventType.locationPermissionDenied ||
    SafetyEventType.locationServicesDisabled ||
    SafetyEventType.locationUpdated =>
      SafetyEventCategory.location,
    SafetyEventType.communicationAttempted ||
    SafetyEventType.communicationFailed ||
    SafetyEventType.communicationHandedOff =>
      SafetyEventCategory.communication,
    SafetyEventType.checkInStarted ||
    SafetyEventType.checkInCompleted =>
      SafetyEventCategory.checkIn,
  };
}

/// A recorded safety event with id, type, and occurrence time.
/// This is the immutable record stored in the rolling buffer and incidents.
@immutable
class RecordedSafetyEvent {
  const RecordedSafetyEvent({
    required this.eventId,
    required this.eventType,
    required this.occurredAt,
    required this.sessionId,
    this.metadata = const {},
  });

  final String eventId;
  final SafetyEventType eventType;
  final DateTime occurredAt;
  final String sessionId;

  /// Privacy-safe metadata (no PII, no coordinates).
  /// Keys are from [SafetyEventMetadataKey].
  final Map<String, String> metadata;

  @override
  bool operator ==(Object other) =>
      other is RecordedSafetyEvent &&
      other.eventId == eventId &&
      other.eventType == eventType &&
      other.occurredAt == occurredAt &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(eventId, eventType, occurredAt, sessionId);
}

/// Privacy-safe metadata keys for recorded events.
abstract final class SafetyEventMetadataKey {
  SafetyEventMetadataKey._();

  static const String vehicleType = 'vehicleType';
  static const String hasRegistration = 'hasRegistration';
  static const String accuracyMeters = 'accuracyMeters';
  static const String isStale = 'isStale';
  static const String failureCategory = 'failureCategory';
  static const String channelType = 'channelType';
  static const String endReason = 'endReason';
}
