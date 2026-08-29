import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import '../../contacts/domain/contacts_repository.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../../location/domain/location_failures.dart';
import '../../location/domain/location_point.dart';
import '../../../core/platform/location_service.dart';
import '../domain/check_in_delivery_status.dart';
import '../domain/check_in_message.dart';
import '../domain/check_in_message_sender.dart';
import '../domain/check_in_settings.dart';
import '../domain/check_in_settings_repository.dart';
import 'check_in_message_builder.dart';

/// Everything one scheduled check-in execution needs from the outside world.
///
/// Keeping the pipeline as a pure function of these seams makes it runnable
/// from BOTH the main isolate (Riverpod controller) and the background
/// notification isolate (manual wiring in `main.dart`) with identical,
/// fully testable behavior.
class CheckInExecutionSeams {
  const CheckInExecutionSeams({
    required this.settingsRepository,
    required this.locationService,
    required this.messageSender,
    required this.contactsRepository,
    required this.now,
    required this.isSosActive,
    required this.scheduleNextExecution,
  });

  final CheckInSettingsRepository settingsRepository;
  final LocationService locationService;
  final CheckInMessageSender messageSender;
  final ContactsRepository contactsRepository;

  /// Injected clock (tests pin this).
  final DateTime Function() now;

  /// SOS has absolute priority: when this returns true the check-in is
  /// skipped and rescheduled, never delayed or cancelled by anything else.
  final bool Function() isSosActive;

  /// Schedules the following execution at [dueAt]. Returning a failure marks
  /// the run [CheckInExecutionStatus.schedulerFailed] so the UI can say the
  /// cadence stopped.
  final Future<Result<void>> Function(DateTime dueAt) scheduleNextExecution;
}

/// What one scheduled execution did, for logging/tests and the controller.
class CheckInExecutionOutcome {
  const CheckInExecutionOutcome({
    required this.status,
    required this.savedSettings,
    this.nextDueAt,
  });

  final CheckInExecutionStatus status;
  final CheckInSettings savedSettings;

  /// When the next execution was scheduled for, when one was.
  final DateTime? nextDueAt;

  bool get locationFresh =>
      status == CheckInExecutionStatus.locationCaptured;
}

/// Runs ONE scheduled Safety Check-In to completion.
///
/// Honest-by-construction rules enforced here:
/// - A captured fix (fresh or labeled stale) is recorded as such; delivery is
///   always user-mediated, so no state ever means "message was sent".
/// - A stale fallback is only used AFTER fresh capture failed, and the message
///   explicitly labels it as a last-known position.
/// - A location failure never cancels the cadence: the next run is scheduled
///   regardless of how this one ended (except when scheduling itself fails).
/// - SOS skips the whole run without touching its alert flow.
Future<CheckInExecutionOutcome> runScheduledCheckIn(
  CheckInExecutionSeams seams,
) async {
  final now = seams.now().toUtc();

  // 1. Load config. Corrupt/unknown payloads already fall back to safe
  //    disabled defaults inside the repository.
  final loaded = await seams.settingsRepository.load();
  late final CheckInSettings settings;
  switch (loaded) {
    case Ok(:final value):
      settings = value;
    case Err():
      return CheckInExecutionOutcome(
        status: CheckInExecutionStatus.disabled,
        savedSettings: CheckInSettings.initial,
      );
  }
  if (!settings.enabled) {
    return CheckInExecutionOutcome(
      status: CheckInExecutionStatus.disabled,
      savedSettings: settings,
    );
  }

  // 2. Recipient gate. The alarm keeps firing so the user can add recipients;
  //    the run itself does nothing and says why.
  if (!settings.hasRecipients) {
    return CheckInExecutionOutcome(
      status: CheckInExecutionStatus.noRecipients,
      savedSettings: await _persist(
        seams,
        settings.copyWith(
          lastAttemptAt: () => now,
          lastExecutionStatus:
              () => CheckInExecutionStatus.noRecipients,
        ),
      ),
    );
  }

  // 3. SOS priority: skip entirely (no location work, no notification),
  //    reschedule so the cadence survives the emergency.
  if (seams.isSosActive()) {
    final nextDue = _nextDue(settings, seams, now);
    await seams.scheduleNextExecution(nextDue);
    return CheckInExecutionOutcome(
      status: CheckInExecutionStatus.skippedForSos,
      savedSettings: await _persist(
        seams,
        settings.copyWith(
          lastAttemptAt: () => now,
          lastExecutionStatus: () => CheckInExecutionStatus.skippedForSos,
          nextScheduledAt: () => nextDue,
        ),
      ),
      nextDueAt: nextDue,
    );
  }

  // 4. One-shot foreground-style location capture via the shared engine.
  final captured = await seams.locationService.getCurrentLocation();
  LocationPoint? point;
  var status = CheckInExecutionStatus.locationUnavailable;
  switch (captured) {
    case Ok(:final value):
      point = value;
      status = value.isStale
          ? CheckInExecutionStatus.staleOnly
          : CheckInExecutionStatus.locationCaptured;
    case Err(:final failure):
      status = switch (failure) {
        LocationServicesDisabledFailure() =>
          CheckInExecutionStatus.servicesDisabled,
        LocationPermissionMissingFailure() =>
          CheckInExecutionStatus.permissionDenied,
        LocationTimeoutFailure() => CheckInExecutionStatus.timeout,
        LocationUnavailableFailure() =>
          CheckInExecutionStatus.locationUnavailable,
        _ => CheckInExecutionStatus.locationUnavailable,
      };
  }

  // 5. Compose + hand off. Delivery stays user-mediated: opening a composer
  //    is recorded as "waiting for you to send", never as sent.
  var communicationFailed = false;
  final resolved = await _resolveRecipients(seams, settings.recipientContactIds);
  if (resolved.isEmpty) {
    // All selected contacts were deleted since enablement: nothing to hand
    // off, and the run says so instead of opening an empty composer.
    return CheckInExecutionOutcome(
      status: CheckInExecutionStatus.noRecipients,
      savedSettings: await _persist(
        seams,
        settings.copyWith(
          lastAttemptAt: () => now,
          lastExecutionStatus: () => CheckInExecutionStatus.noRecipients,
        ),
      ),
    );
  }
  if (resolved.isNotEmpty) {
    final message = CheckInMessage(
      recipientPhoneNumbers: [
        for (final contact in resolved)
          if (contact.phoneNumber.isNotEmpty) contact.phoneNumber,
      ],
      recipientEmails: [
        for (final contact in resolved)
          if (contact.email != null && contact.email!.isNotEmpty)
            contact.email!,
      ],
      body: buildCheckInMessageBody(
        point: point,
        missedCount: settings.missedCount,
      ),
      missedCount: settings.missedCount,
      composedAt: seams.now(),
    );
    final sendResult = await seams.messageSender.send(message);
    switch (sendResult) {
      case Ok():
        break;
      case Err():
        communicationFailed = true;
    }
  }

  // 6. Record honestly + keep the cadence alive.
  final effectiveStatus = communicationFailed
      ? CheckInExecutionStatus.communicationFailed
      : status;
  final nextDue = _nextDue(settings, seams, now);
  final scheduleOk =
      (await seams.scheduleNextExecution(nextDue)) is Ok;
  final saved = await _persist(
    seams,
    settings.copyWith(
      lastAttemptAt: () => now,
      lastSuccessfulLocationAt: point != null && !point.isStale
          ? () => now
          : null,
      lastExecutionStatus: () => scheduleOk
          ? effectiveStatus
          : CheckInExecutionStatus.schedulerFailed,
      nextScheduledAt: () => scheduleOk ? nextDue : null,
    ),
  );
  _logOutcome(
    scheduleOk ? effectiveStatus : CheckInExecutionStatus.schedulerFailed,
    point != null && !point.isStale,
  );
  return CheckInExecutionOutcome(
    status: scheduleOk ? effectiveStatus : CheckInExecutionStatus.schedulerFailed,
    savedSettings: saved,
    nextDueAt: scheduleOk ? nextDue : null,
  );
}

void _logOutcome(CheckInExecutionStatus status, bool freshFix) {
  // Privacy-preserving diagnostics for real-device validation: outcome label
  // and fix freshness only — never coordinates, numbers, emails or URLs.
  if (kDebugMode) {
    debugPrint(
      '[CheckInExecution] status=${status.name} fresh=$freshFix',
    );
  }
}

DateTime _nextDue(
  CheckInSettings settings,
  CheckInExecutionSeams seams,
  DateTime nowUtc,
) {
  final base = settings.lastAcknowledgedAt ?? nowUtc;
  var due = base.add(settings.interval.duration);
  while (!due.isAfter(nowUtc)) {
    due = due.add(settings.interval.duration);
  }
  return due.toUtc();
}

Future<List<TrustedContact>> _resolveRecipients(
  CheckInExecutionSeams seams,
  List<String> ids,
) async {
  final result = await seams.contactsRepository.loadContacts();
  switch (result) {
    case Ok(:final value):
      final idSet = ids.toSet();
      return [
        for (final contact in value)
          if (idSet.contains(contact.id)) contact,
      ];
    case Err():
      return const [];
  }
}

Future<CheckInSettings> _persist(
  CheckInExecutionSeams seams,
  CheckInSettings settings,
) async {
  await seams.settingsRepository.save(settings);
  return settings;
}
