import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/platform/local_notifications.dart';
import '../domain/fake_call_alert.dart';

/// Fixed id for the fake-call notification; upserted in place.
const int fakeCallNotificationId = 3001;

/// Tap payload routed to the incoming-call screen by the app entrypoint.
const String fakeCallNotificationPayload = 'fake-call';

/// Android channel carrying the fake incoming-call alert.
const String fakeCallChannelId = 'fake_call';
const String fakeCallChannelName = 'Incoming call';

/// [FakeCallNotifier] backed by the shared local-notifications plugin.
///
/// Same inexact scheduling pattern as check-in reminders (no exact-alarm
/// permission; may drift on throttled devices — acceptable for a simulated
/// call). Content is generic and local; no names are logged.
class FakeCallLocalNotifier implements FakeCallNotifier {
  FakeCallLocalNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _timeZoneInitialized = false;

  static const NotificationDetails _incomingDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      fakeCallChannelId,
      fakeCallChannelName,
      channelDescription: 'Simulated incoming calls.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    ),
  );

  /// The plugin REJECTS non-future dates with an ArgumentError (an `Error`,
  /// not an `Exception`) — clamp forward like the check-in scheduler does.
  tz.TZDateTime _clampFuture(DateTime fireAt) {
    final earliest = tz.TZDateTime.from(
        DateTime.now().toUtc().add(const Duration(seconds: 3)), tz.local);
    final target = tz.TZDateTime.from(fireAt.toUtc(), tz.local);
    return target.isAfter(earliest) ? target : earliest;
  }

  Future<bool> _initializeIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      await ensureLocalNotificationsInitialized(_plugin);
      if (!_timeZoneInitialized) {
        tz_data.initializeTimeZones();
        try {
          tz.setLocalLocation(
              tz.getLocation(await FlutterTimezone.getLocalTimezone()));
        } catch (_) {
          tz.setLocalLocation(tz.getLocation('UTC'));
        }
        _timeZoneInitialized = true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> scheduleIncomingCall({
    required String callerName,
    required DateTime fireAt,
  }) async {
    if (!await _initializeIfNeeded()) return;
    try {
      await _plugin.zonedSchedule(
        id: fakeCallNotificationId,
        title: 'Simulated incoming call',
        body: 'Simulated: $callerName is calling…',
        scheduledDate: _clampFuture(fireAt),
        notificationDetails: _incomingDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: fakeCallNotificationPayload,
      );
    } catch (_) {
      // Best-effort fallback only; the Dart timer is primary.
    }
  }

  @override
  Future<void> showIncomingCallNow({required String callerName}) async {
    if (!await _initializeIfNeeded()) return;
    try {
      await _plugin.show(
        id: fakeCallNotificationId,
        title: 'Simulated incoming call',
        body: 'Simulated: $callerName is calling…',
        notificationDetails: _incomingDetails,
        payload: fakeCallNotificationPayload,
      );
    } catch (_) {
      // Best-effort fallback only.
    }
  }

  @override
  Future<void> cancelIncomingCall() async {
    try {
      await _plugin.cancel(id: fakeCallNotificationId);
    } catch (_) {
      // Idempotent; never throws.
    }
  }
}
