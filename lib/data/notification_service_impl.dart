import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/error/failures.dart';
import '../core/platform/local_notifications.dart';
import '../core/platform/notification_service.dart';
import '../core/result/result.dart';

/// Fixed id for the SOS notification; sharing it across show/cancel lets the
/// plugin upsert in place and remove it reliably.
const int sosNotificationId = 1001;

/// Android channel carrying all SOS alerts.
const String sosNotificationChannelId = 'sos_alert';
const String sosNotificationChannelName = 'SOS alerts';

/// Generic, privacy-preserving notification content. No contact names, phone
/// numbers, locations or emergency details are ever placed here.
const String sosActiveNotificationTitle = 'SOS ACTIVE';
const String sosActiveNotificationBody =
    'Open GuardianHer to manage your SOS.';
const String sosStoppingNotificationTitle = 'SOS';
const String sosStoppingNotificationBody = 'Stopping SOS…';

/// [NotificationService] backed by `flutter_local_notifications`.
///
/// The notification is a secondary, best-effort capability: every operation
/// catches platform errors and returns a failure instead of throwing, so a
/// denied permission or a broken plugin can never disturb the SOS state
/// machine. The Android channel, notification id and generic content live
/// here, out of the application layer.
///
/// The plugin instance is shared (see [flutterLocalNotificationsPluginProvider])
/// so SOS notifications and check-in reminders use one platform channel; tap
/// navigation is routed through [localNotificationsTapHandler].
class FlutterLocalNotificationsNotificationService
    implements NotificationService {
  FlutterLocalNotificationsNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const NotificationDetails _sosDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      sosNotificationChannelId,
      sosNotificationChannelName,
      channelDescription: 'Ongoing alerts during an active SOS session.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.service,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: true,
      // Sound and vibration are intentionally off: haptics are driven by the
      // bounded SOS vibration pattern so nothing can loop here.
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Initializes the plugin lazily on Android. Returns `false` (no-op) on
  /// other platforms so the app never crashes there. Phase 3B targets Android.
  Future<bool> _initializeIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return ensureLocalNotificationsInitialized(_plugin);
  }

  @override
  Future<Result<bool>> isPermissionGranted() async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(true);
      }
      final enabled = await _android?.areNotificationsEnabled();
      return Ok(enabled ?? true);
    } catch (_) {
      return Err(NotificationPermissionDeniedFailure());
    }
  }

  @override
  Future<Result<void>> requestPermission() async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(null);
      }
      await _android?.requestNotificationsPermission();
      return const Ok(null);
    } catch (_) {
      return Err(NotificationPermissionDeniedFailure());
    }
  }

  @override
  Future<Result<void>> showSosActive() => _show(
        title: sosActiveNotificationTitle,
        body: sosActiveNotificationBody,
      );

  @override
  Future<Result<void>> showSosStopping() => _show(
        title: sosStoppingNotificationTitle,
        body: sosStoppingNotificationBody,
      );

  Future<Result<void>> _show({
    required String title,
    required String body,
  }) async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(null);
      }
      await _plugin.show(
        id: sosNotificationId,
        title: title,
        body: body,
        notificationDetails: _sosDetails,
        payload: 'sos',
      );
      return const Ok(null);
    } catch (_) {
      return Err(PlatformActionFailure('Unable to show the notification.'));
    }
  }

  @override
  Future<Result<void>> cancelSos() async {
    try {
      if (!await _initializeIfNeeded()) {
        return const Ok(null);
      }
      await _plugin.cancel(id: sosNotificationId);
      return const Ok(null);
    } catch (_) {
      return Err(PlatformActionFailure('Unable to remove the notification.'));
    }
  }
}