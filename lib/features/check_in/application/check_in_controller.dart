import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/notification_service.dart';
import '../../../core/providers.dart';
import '../../../core/result/result.dart';
import '../../contacts/application/contacts_providers.dart';
import '../../contacts/domain/contacts_repository.dart';
import '../../contacts/domain/trusted_contact.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../sos/application/sos_providers.dart';
import '../../sos/application/sos_state.dart';
import '../domain/check_in_delivery_status.dart';
import '../domain/check_in_failures.dart';
import '../domain/check_in_interval.dart';
import '../domain/check_in_message.dart';
import '../domain/check_in_message_sender.dart';
import '../domain/check_in_scheduler.dart';
import '../domain/check_in_settings.dart';
import '../domain/check_in_settings_repository.dart';
import 'check_in_execution_service.dart';
import 'check_in_message_builder.dart';
import 'check_in_providers.dart';
import 'check_in_state.dart';
import 'check_in_timeline.dart';

/// Owns the Safety Check-In workflow.
///
/// Pure scheduling/acknowledgment logic lives in [computeNextDueAt] and
/// [computeMissedCheckIns]; this controller orchestrates the platform seams
/// (settings storage, reminder scheduler, notification permission, one-shot
/// location capture, message sender) around them. All four reliability
/// controls are implemented here:
///
/// * opt-in enablement (default disabled);
/// * configurable interval and recipient set;
/// * a scheduled reminder per interval, re-scheduled on acknowledgment;
/// * missed escalation — an unacknowledged check-in re-notifies and the next
///   message honestly reports how many were skipped.
///
/// A location failure can never cancel a check-in: the message is sent
/// (through the user-confirmed sender) with an explicit "no location" line.
class CheckInController extends Notifier<CheckInState> {
  CheckInSettingsRepository get _repository =>
      ref.read(checkInSettingsRepositoryProvider);
  CheckInScheduler get _scheduler => ref.read(checkInSchedulerProvider);
  NotificationService get _notification =>
      ref.read(notificationServiceProvider);
  CheckInMessageSender get _sender => ref.read(checkInMessageSenderProvider);
  ContactsRepository get _contacts => ref.read(contactsRepositoryProvider);
  DateTime Function() get _now => ref.read(checkInClockProvider);

  @override
  CheckInState build() {
    _load();
    return const CheckInState(
      settings: CheckInSettings.initial,
    );
  }

  Future<void> _load() async {
    final result = await _repository.load();
    final settings = result.isOk ? result.getOrNull()! : CheckInSettings.initial;
    if (!settings.enabled) {
      state = CheckInState(settings: settings, loaded: true);
      return;
    }
    // The timeline refresh touches platform scheduling; a failure there must
    // never leave the controller stuck unloaded (observed on device when the
    // plugin rejected a non-future alarm date).
    try {
      await _refreshTimeline(settings);
    } catch (_) {
      state = CheckInState(settings: settings, loaded: true);
    }
  }

  /// Enables check-ins (or updates an enabled check-in) with the chosen
  /// [interval] and [recipientContactIds]. Starts a fresh schedule.
  Future<Result<void>> enable({
    required CheckInInterval interval,
    required List<String> recipientContactIds,
  }) async {
    if (recipientContactIds.isEmpty) {
      return const Err(CheckInNoRecipientsFailure());
    }
    final granted = await _ensureNotificationPermission();
    if (granted is Err) {
      return granted;
    }
    final now = _now().toUtc();
    final nextDue = computeNextDueAt(
      lastAcknowledgedAt: now,
      interval: interval,
      missedCount: 0,
    );
    final settings = state.settings.copyWith(
      enabled: true,
      interval: interval,
      recipientContactIds: recipientContactIds,
      lastAcknowledgedAt: () => now,
      missedCount: 0,
      lastAttemptAt: () => null,
      lastSuccessfulLocationAt: () => null,
      lastExecutionStatus: () => null,
      nextScheduledAt: () => nextDue,
    );
    final saved = await _repository.save(settings);
    if (saved is Err) {
      return saved;
    }
    // The scheduled fire runs the EXECUTION pipeline (location → honest
    // status → user-mediated handoff), not just a reminder.
    final scheduled = await _scheduler.scheduleExecution(nextDue);
    state = CheckInState(
      settings: settings,
      loaded: true,
      statusMessage: scheduled.isOk
          ? 'Check-in scheduled ${interval.label.toLowerCase()}.'
          : 'Check-in saved, but the reminder could not be scheduled.',
    );
    return scheduled;
  }

  /// Disables check-ins and cancels the pending execution.
  Future<Result<void>> disable() async {
    final settings = state.settings.copyWith(
      enabled: false,
      lastAcknowledgedAt: () => null,
      missedCount: 0,
      lastAttemptAt: () => state.settings.lastAttemptAt,
      nextScheduledAt: () => null,
    );
    final saved = await _repository.save(settings);
    await _scheduler.cancelAll();
    state = CheckInState(settings: settings, loaded: true);
    return saved;
  }

  /// Re-evaluates the timeline: marks the check-in due when its reminder time
  /// has arrived, and escalates (increments [CheckInState.missedCount] and
  /// re-notifies) whenever an interval passed without acknowledgment.
  ///
  /// Called at app/feature start and whenever the check-in screen opens, so
  /// missed escalation works even if the app was killed.
  Future<void> refresh() async {
    final current = state;
    if (!current.settings.enabled || !current.loaded) {
      return;
    }
    await _refreshTimeline(current.settings);
  }

  Future<void> _refreshTimeline(CheckInSettings settings) async {
    final lastAck = settings.lastAcknowledgedAt;
    final now = _now().toUtc();
    if (lastAck == null) {
      // Enabled but never started: begin the first interval now.
      final nextDue = computeNextDueAt(
        lastAcknowledgedAt: now,
        interval: settings.interval,
        missedCount: 0,
      );
      final reset = settings.copyWith(
        lastAcknowledgedAt: () => now,
        missedCount: 0,
        nextScheduledAt: () => nextDue,
      );
      await _repository.save(reset);
      await _scheduler.scheduleExecution(nextDue);
      state = CheckInState(settings: reset, loaded: true);
      return;
    }

    final missed = computeMissedCheckIns(
      lastAcknowledgedAt: lastAck,
      interval: settings.interval,
      now: now,
    );
    final escalated = missed > settings.missedCount;
    final nextDue = computeNextDueAt(
      lastAcknowledgedAt: lastAck,
      interval: settings.interval,
      missedCount: missed,
    );
    var updated = settings.copyWith(missedCount: missed);
    if (escalated) {
      // A check-in went unanswered: re-notify immediately (reminder-style)
      // and keep the execution cadence aligned to the timeline.
      await _scheduler.scheduleReminder(now, missedCount: missed);
    }
    // Always re-assert the next execution on every refresh: the OS can drop
    // the pending alarm (user Force-stop, OEM task killers, some reboots),
    // and without this the cadence stays silently dead until the NEXT
    // escalation even though the user opened the app. Upserting the same
    // notification id makes this idempotent.
    if (updated.nextScheduledAt != nextDue) {
      updated = updated.copyWith(nextScheduledAt: () => nextDue);
      await _repository.save(updated);
    }
    await _scheduler.scheduleExecution(nextDue);
    state = CheckInState(
      settings: updated,
      loaded: true,
      missedCount: missed,
      isDue: !now.isBefore(nextDue),
    );
  }

  /// Confirms the check-in: captures a one-shot location, composes the message
  /// and hands it to the user-confirmed sender, then starts the next interval.
  Future<Result<void>> acknowledge() async {
    final current = state;
    if (current.isWorking || !current.settings.enabled) {
      return const Ok(null);
    }
    state = current.copyWith(isWorking: true);

    // Best-effort location: a failure never cancels the check-in.
    await ref.read(locationControllerProvider.notifier).captureLocation();
    final location = ref.read(locationControllerProvider);
    final point = location.status == LocationStatus.captured
        ? location.point
        : null;

    final (recipientNumbers, recipientEmails) = await _resolveRecipients(
      current.settings.recipientContactIds,
    );
    final message = CheckInMessage(
      recipientPhoneNumbers: recipientNumbers,
      recipientEmails: recipientEmails,
      body: buildCheckInMessageBody(
        point: point,
        missedCount: current.missedCount,
      ),
      missedCount: current.missedCount,
      composedAt: _now().toUtc(),
    );

    final sent = await _sender.send(message);

    final now = _now().toUtc();
    final nextDue = computeNextDueAt(
      lastAcknowledgedAt: now,
      interval: current.settings.interval,
      missedCount: 0,
    );
    final settings = current.settings.copyWith(
      lastAcknowledgedAt: () => now,
      missedCount: 0,
      nextScheduledAt: () => nextDue,
    );
    await _repository.save(settings);
    await _scheduler.scheduleExecution(nextDue);

    state = CheckInState(
      settings: settings,
      loaded: true,
      statusMessage: sent.fold(
        (_) => 'Check-in message opened for sending.',
        (failure) => failure.message,
      ),
    );
    return sent;
  }

  /// Foreground execution path: runs the SAME pipeline as the background
  /// isolate (see [runScheduledCheckIn]) with real seams, including the SOS
  /// priority guard. Used when the user taps the fired notification or opens
  /// the check-in screen while a run is due.
  Future<CheckInExecutionOutcome> runDueCheckIn() async {
    final outcome = await runScheduledCheckIn(
      CheckInExecutionSeams(
        settingsRepository: _repository,
        locationService: ref.read(locationServiceProvider),
        messageSender: _sender,
        contactsRepository: _contacts,
        now: _now,
        isSosActive: () =>
            ref.read(sosControllerProvider) is SosActive,
        scheduleNextExecution: _scheduler.scheduleExecution,
      ),
    );
    state = CheckInState(
      settings: outcome.savedSettings,
      loaded: true,
      statusMessage:
          outcome.status == CheckInExecutionStatus.disabled
              ? null
              : outcome.status.label,
    );
    return outcome;
  }

  Future<Result<void>> _ensureNotificationPermission() async {
    await _notification.requestPermission();
    final granted = await _notification.isPermissionGranted();
    if (granted is Ok<bool> && granted.value) {
      return const Ok(null);
    }
    return const Err(CheckInSchedulingFailure(
      'Enable notifications in your device settings to use check-ins.',
    ));
  }

  /// Resolves the chosen contact ids to their phone numbers and (optional)
  /// email addresses, preserving the contacts' priority order.
  Future<(List<String>, List<String>)> _resolveRecipients(
    List<String> ids,
  ) async {
    final loaded = await _contacts.loadContacts();
    final contacts = loaded.isOk
        ? loaded.getOrNull()!
        : const <TrustedContact>[];
    final numbers = <String>[];
    final emails = <String>{};
    for (final contact in contacts) {
      if (!ids.contains(contact.id)) continue;
      numbers.add(contact.phoneNumber);
      final email = contact.email;
      if (email != null && !emails.contains(email)) emails.add(email);
    }
    return (numbers, emails.toList(growable: false));
  }
}