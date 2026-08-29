import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single shared `flutter_local_notifications` plugin instance.
///
/// Both the SOS notification service and the check-in scheduler drive the same
/// plugin so there is exactly one platform channel and one notification-tap
/// stream. The composition root wires this provider; consumers never create
/// their own plugin.
final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

/// Notification-tap dispatch target.
///
/// The app entrypoint (which owns routing) sets this so both the SOS and
/// check-in notifications navigate to the right screen. Every consumer's
/// initialization registers a callback that routes through this handler, so a
/// later initialization can never silently drop tap navigation.
void Function(String? payload)? localNotificationsTapHandler;

/// Background-notification-response dispatch target.
///
/// The check-in feature assigns its `@pragma('vm:entry-point')` execution
/// dispatcher here from `main.dart` BEFORE any consumer initializes, so the
/// scheduled-execution isolate can wake when an alarm fires while the app is
/// dead. Core never imports features; the dependency points outward.
Future<void> Function(NotificationResponse response)?
    localNotificationsBackgroundHandler;

/// Plugin-required top-level entry point for background notification
/// responses (`flutter_local_notifications` rejects closures here). Forwards
/// to [localNotificationsBackgroundHandler], which features assign.
@pragma('vm:entry-point')
Future<void> localNotificationsBackgroundTrampoline(
  NotificationResponse response,
) async {
  await localNotificationsBackgroundHandler?.call(response);
}

bool _localNotificationsInitialized = false;

/// Initializes the shared plugin exactly once.
///
/// Idempotent and safe to call from every consumer: re-initialization
/// re-registers the same [localNotificationsTapHandler] dispatcher rather than
/// a consumer-specific callback.
Future<bool> ensureLocalNotificationsInitialized(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (_localNotificationsInitialized) {
    return true;
  }
  try {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          localNotificationsTapHandler?.call(response.payload),
      onDidReceiveBackgroundNotificationResponse:
          localNotificationsBackgroundTrampoline,
    );
  } catch (_) {
    // Catch ALL (the platform interface raises LateError before binding when
    // no implementation is registered). Boot must never crash over
    // notifications; consumers treat false as "skip scheduling".
    return false;
  }
  // A tap that LAUNCHED the app (process was dead) is not re-delivered
  // through the response callback above — the plugin exposes it as launch
  // details exactly once. Without this, cold notification taps opened the
  // app on its default screen instead of the SOS/check-in destination.
  _localNotificationsInitialized = true;
  try {
    final launchDetails = await plugin.getNotificationAppLaunchDetails();
    if ((launchDetails?.didNotificationLaunchApp ?? false) &&
        launchDetails?.notificationResponse != null) {
      localNotificationsTapHandler?.call(
        launchDetails!.notificationResponse!.payload,
      );
    }
  } catch (_) {
    // Launch-detail dispatch is best-effort; warm taps still route through
    // onDidReceiveNotificationResponse.
  }
  return true;
}