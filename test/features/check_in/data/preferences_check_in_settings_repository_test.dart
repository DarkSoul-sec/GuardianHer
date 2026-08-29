import 'package:flutter_test/flutter_test.dart';

import 'package:guardianher/core/result/result.dart';
import 'package:guardianher/features/check_in/data/preferences_check_in_settings_repository.dart';
import 'package:guardianher/features/check_in/domain/check_in_delivery_status.dart';
import 'package:guardianher/features/check_in/domain/check_in_interval.dart';
import 'package:guardianher/features/check_in/domain/check_in_settings.dart';

import '../../../helpers/fakes.dart';

void main() {
  late FakePreferencesService preferences;
  late PreferencesCheckInSettingsRepository repository;

  setUp(() {
    preferences = FakePreferencesService();
    repository = PreferencesCheckInSettingsRepository(preferences);
  });

  test('returns the disabled default when nothing is stored', () async {
    final result = await repository.load();
    expect(result.isOk, isTrue);
    final settings = result.getOrNull()!;
    expect(settings.enabled, isFalse);
    expect(settings.interval, CheckInInterval.minutes60);
    expect(settings.recipientContactIds, isEmpty);
  });

  test('round-trips an enabled configuration', () async {
    final settings = CheckInSettings(
      enabled: true,
      interval: CheckInInterval.minutes120,
      recipientContactIds: const ['a', 'b'],
      graceMinutes: 15,
      lastAcknowledgedAt: DateTime.utc(2026, 1, 1, 12),
      missedCount: 2,
    );
    final saved = await repository.save(settings);
    expect(saved, isA<Ok>());
    final loaded = await repository.load();
    final restored = loaded.getOrNull()!;
    expect(restored.enabled, isTrue);
    expect(restored.interval, CheckInInterval.minutes120);
    expect(restored.recipientContactIds, ['a', 'b']);
    expect(restored.graceMinutes, 15);
    expect(restored.lastAcknowledgedAt, DateTime.utc(2026, 1, 1, 12));
    expect(restored.missedCount, 2);
  });

  test('writes a versioned document and round-trips execution fields',
      () async {
    await repository.save(
      CheckInSettings(
        enabled: true,
        interval: CheckInInterval.minutes180,
        recipientContactIds: const ['a'],
        lastAcknowledgedAt: DateTime.utc(2026, 1, 1, 12),
        lastAttemptAt: DateTime.utc(2026, 1, 1, 13),
        lastSuccessfulLocationAt: DateTime.utc(2026, 1, 1, 12, 59),
        lastExecutionStatus: CheckInExecutionStatus.locationCaptured,
        nextScheduledAt: DateTime.utc(2026, 1, 1, 14),
      ),
    );
    final stored = await preferences.getString(checkInSettingsStorageKey);
    expect(stored, contains('"version":1'));
    final restored = (await repository.load()).getOrNull()!;
    expect(restored.lastAttemptAt, DateTime.utc(2026, 1, 1, 13));
    expect(restored.lastSuccessfulLocationAt, DateTime.utc(2026, 1, 1, 12, 59));
    expect(
      restored.lastExecutionStatus,
      CheckInExecutionStatus.locationCaptured,
    );
    expect(restored.nextScheduledAt, DateTime.utc(2026, 1, 1, 14));
  });

  test('loads a legacy document written before the version field', () async {
    await preferences.setString(
      checkInSettingsStorageKey,
      '{"enabled":true,"interval_minutes":60,"recipient_ids":["a"],'
          '"grace_minutes":10,"missed_count":1}',
    );
    final restored = (await repository.load()).getOrNull()!;
    expect(restored.enabled, isTrue);
    expect(restored.lastAttemptAt, isNull);
    expect(restored.lastExecutionStatus, isNull);
  });

  test('treats an unsupported future version as corrupt data', () async {
    await preferences.setString(
      checkInSettingsStorageKey,
      '{"version":99,"enabled":true}',
    );
    final restored = (await repository.load()).getOrNull()!;
    expect(restored.enabled, isFalse);
  });

  test('an unknown status name decodes to null instead of crashing',
      () async {
    await preferences.setString(
      checkInSettingsStorageKey,
      '{"version":1,"enabled":true,"last_execution_status":"huh"}',
    );
    final restored = (await repository.load()).getOrNull()!;
    expect(restored.enabled, isTrue);
    expect(restored.lastExecutionStatus, isNull);
  });

  test('falls back to the disabled default on corrupt data', () async {
    await preferences.setString(checkInSettingsStorageKey, 'not json');
    final result = await repository.load();
    expect(result.isOk, isTrue);
    expect(result.getOrNull()!.enabled, isFalse);
  });

  test('falls back to a valid interval when the stored value is unknown',
      () async {
    await preferences.setString(
      checkInSettingsStorageKey,
      '{"enabled":true,"interval_minutes":17,"recipient_ids":[]}',
    );
    final loaded = await repository.load();
    expect(loaded.getOrNull()!.interval, CheckInInterval.minutes60);
  });
}