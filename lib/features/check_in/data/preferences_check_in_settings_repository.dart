import 'dart:convert';

import '../../../core/error/failures.dart';
import '../../../core/platform/preferences_service.dart';
import '../../../core/result/result.dart';
import '../domain/check_in_delivery_status.dart';
import '../domain/check_in_interval.dart';
import '../domain/check_in_settings.dart';
import '../domain/check_in_settings_repository.dart';

/// Storage key for the serialized check-in settings document.
const String checkInSettingsStorageKey = 'safety_check_in_settings_v1';

/// Current document version. Bump on breaking shape changes; the loader
/// treats an unknown version like corrupt data and falls back to safe
/// defaults (disabled), so a future downgrade can never misread fields.
const int checkInSettingsDocumentVersion = 1;

/// [CheckInSettingsRepository] backed by [PreferencesService].
///
/// Settings are app-local and non-sensitive (recipients are stored as trusted
/// contact ids, never phone numbers), so shared_preferences is the right store
/// — matching the contacts-preference precedent for non-sensitive data.
class PreferencesCheckInSettingsRepository
    implements CheckInSettingsRepository {
  const PreferencesCheckInSettingsRepository(this._preferences);

  final PreferencesService _preferences;

  @override
  Future<Result<CheckInSettings>> load() async {
    try {
      final raw = await _preferences.getString(checkInSettingsStorageKey);
      if (raw == null || raw.isEmpty) {
        return const Ok(CheckInSettings.initial);
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return Ok(checkInSettingsFromJson(decoded));
    } on Exception {
      // Corrupt/unknown payload: fall back to the safe default (disabled).
      return const Ok(CheckInSettings.initial);
    }
  }

  @override
  Future<Result<void>> save(CheckInSettings settings) async {
    try {
      await _preferences.setString(
        checkInSettingsStorageKey,
        jsonEncode(checkInSettingsToJson(settings)),
      );
      return const Ok(null);
    } on Exception {
      return Err(StorageFailure('Check-in settings could not be saved.'));
    }
  }
}

Map<String, dynamic> checkInSettingsToJson(CheckInSettings settings) => {
      'version': checkInSettingsDocumentVersion,
      'enabled': settings.enabled,
      'interval_minutes': settings.interval.minutes,
      'recipient_ids': settings.recipientContactIds,
      'grace_minutes': settings.graceMinutes,
      'last_acknowledged_at': settings.lastAcknowledgedAt?.toIso8601String(),
      'missed_count': settings.missedCount,
      'last_attempt_at': settings.lastAttemptAt?.toIso8601String(),
      'last_successful_location_at':
          settings.lastSuccessfulLocationAt?.toIso8601String(),
      'last_execution_status': settings.lastExecutionStatus?.name,
      'next_scheduled_at': settings.nextScheduledAt?.toIso8601String(),
    };

CheckInSettings checkInSettingsFromJson(Map<String, dynamic> json) {
  final version = json['version'];
  if (version != null && version != checkInSettingsDocumentVersion) {
    throw const FormatException('Unsupported check-in settings version');
  }
  final lastAcknowledged = json['last_acknowledged_at'] as String?;
  final lastAttempt = json['last_attempt_at'] as String?;
  final lastSuccessfulLocation =
      json['last_successful_location_at'] as String?;
  final nextScheduled = json['next_scheduled_at'] as String?;
  return CheckInSettings(
    enabled: json['enabled'] as bool? ?? false,
    interval: CheckInInterval.fromMinutes(
      json['interval_minutes'] as int? ?? CheckInInterval.minutes60.minutes,
    ),
    recipientContactIds: (json['recipient_ids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    graceMinutes: json['grace_minutes'] as int? ?? 10,
    lastAcknowledgedAt: lastAcknowledged == null
        ? null
        : DateTime.tryParse(lastAcknowledged)?.toUtc(),
    missedCount: (json['missed_count'] as int?) ?? 0,
    lastAttemptAt:
        lastAttempt == null ? null : DateTime.tryParse(lastAttempt)?.toUtc(),
    lastSuccessfulLocationAt: lastSuccessfulLocation == null
        ? null
        : DateTime.tryParse(lastSuccessfulLocation)?.toUtc(),
    lastExecutionStatus: _executionStatusFromName(
      json['last_execution_status'] as String?,
    ),
    nextScheduledAt: nextScheduled == null
        ? null
        : DateTime.tryParse(nextScheduled)?.toUtc(),
  );
}

CheckInExecutionStatus? _executionStatusFromName(String? name) {
  if (name == null) {
    return null;
  }
  for (final status in CheckInExecutionStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  return null;
}