import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/platform/local_notifications.dart';
import '../../../core/result/result.dart';
import '../domain/check_in_failures.dart';
import '../domain/check_in_scheduler.dart';

/// Fixed id for the pending check-in reminder; upserted in place by the plugin.
const int checkInNotificationId = 2001;

/// Android channel carrying check-in reminders.
const String checkInNotificationChannelId = 'safety_check_in';
const String checkInNotificationChannelName = 'Safety check-in';

/// Tap payload routed to the check-in screen by the app entrypoint.
const String checkInNotificationPayload = 'check-in';

/// Payload marking a scheduled EXECUTION. When the background-notification
/// isolate wakes (registered in `main.dart`), a response carrying this
/// payload runs the check-in pipeline headlessly; any other payload is plain
/// navigation. Tapping the notification always opens the app as well, so the
/// foreground path can complete whatever the background could not.
const String checkInExecutionPayload = 'check-in-run';

/// Generic, privacy-preserving reminder content (no names, numbers or
/// locations). Wording escalates with missed check-ins.
String checkInReminderTitle(int missedCount) => missedCount > 0
    ? 'Safety check-in missed'
    : 'Safety check-in';

const String checkInReminderBody =
    'Open GuardianHer to confirm you are safe.';

/// [CheckInScheduler] backed by the shared `flutter_local_notifications`
/// plugin's exact-style scheduling (zoned, local-time).
///
/// Uses `inexactAllowWhileIdle` so no exact-alarm permission is required;
/// reminders may drift a few minutes on heavily throttled devices, which is
/// acceptable for a check-in nudge. All content is generic and privacy
/// preserving.
class FlutterLocalNotificationsCheckInScheduler implements CheckInScheduler {
  FlutterLocalNotificationsCheckInScheduler({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const NotificationDetails _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      checkInNotificationChannelId,
      checkInNotificationChannelName,
      channelDescription: 'Scheduled safety check-in reminders.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    ),
  );

  bool _timeZoneInitialized = false;

  /// The plugin REJECTS non-future dates with an ArgumentError (an `Error`,
  /// not an `Exception`), which would blow past `on Exception` handlers and
  /// kill callers mid-flight. Clock drift between computing a due time and
  /// scheduling it makes this reachable in practice — clamp forward instead.
  tz.TZDateTime _clampFuture(DateTime dueAt) {
    final earliest =
        tz.TZDateTime.from(DateTime.now().toUtc().add(const Duration(seconds: 3)), tz.local);
    final target = tz.TZDateTime.from(dueAt.toUtc(), tz.local);
    return target.isAfter(earliest) ? target : earliest;
  }

  Future<bool> _initializeIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    await ensureLocalNotificationsInitialized(_plugin);
    await _ensureTimeZone();
    return true;
  }

  /// Loads the IANA time-zone database and pins the device's local zone so
  /// `zonedSchedule` fires at the right local time. Falls back to UTC on any
  /// platform error (reminders would drift by the offset) rather than throw.
  Future<void> _ensureTimeZone() async {
    if (_timeZoneInitialized) {
      return;
    }
    try {
      tz_data.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _timeZoneInitialized = true;
  }

  @override
  Future<Result<void>> scheduleReminder(
    DateTime dueAt, {
    required int missedCount,
  }) async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(null);
      }
      final scheduledAt = _clampFuture(dueAt);
      await _plugin.zonedSchedule(
        id: checkInNotificationId,
        title: checkInReminderTitle(missedCount),
        body: checkInReminderBody,
        scheduledDate: scheduledAt,
        notificationDetails: _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: checkInNotificationPayload,
      );
      return const Ok(null);
    } catch (_) {
      // Catch ALL (not just Exception): the plugin raises ArgumentError.
      return Err(CheckInSchedulingFailure());
    }
  }

  @override
  Future<Result<void>> scheduleExecution(DateTime dueAt) async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(null);
      }
      final scheduledAt = _clampFuture(dueAt);
      await _plugin.zonedSchedule(
        id: checkInNotificationId,
        title: checkInReminderTitle(0),
        body: checkInReminderBody,
        scheduledDate: scheduledAt,
        notificationDetails: _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: checkInExecutionPayload,
      );
      return const Ok(null);
    } catch (_) {
      return Err(CheckInSchedulingFailure());
    }
  }

  @override
  Future<Result<void>> cancelAll() async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(null);
      }
      await _plugin.cancel(id: checkInNotificationId);
      return const Ok(null);
    } catch (_) {
      return Err(CheckInSchedulingFailure());
    }
  }
}