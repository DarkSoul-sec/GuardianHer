import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../app/router/app_router.dart';

/// Home-screen SOS launcher widget routing.
///
/// The widget is a pure launcher: tapping it opens the app with a
/// `guardianher://sos` URI (set natively in `SosWidgetProvider`). It never
/// captures location or runs app logic in the background — the app routes to
/// the SOS screen on the Flutter side when it comes to the foreground.
const sosWidgetUriScheme = 'guardianher';
const sosWidgetUriHost = 'sos';

/// URI host used when the shake detector arms SOS (`guardianher://shakesos`).
const shakesosUriHost = 'shakesos';

/// URI host used when the Quick Settings SOS tile is tapped
/// (`guardianher://tilesos`, Phase B). Like a shake, this ARMS the SOS
/// workflow — not merely navigation.
const tileSosUriHost = 'tilesos';

/// Qualified name of the native widget provider, used when pinning the widget
/// from within the app.
const sosWidgetProviderName = 'com.guardianher.app.SosWidgetProvider';

/// Whether [uri] is the home-screen SOS widget launch URI.
bool isSosWidgetUri(Uri? uri) =>
    uri != null &&
    uri.scheme == sosWidgetUriScheme &&
    (uri.host == sosWidgetUriHost || uri.path == '/sos');

/// Whether [uri] is a shake-triggered SOS launch (arms the workflow, not just
/// navigation).
bool isShakeSosUri(Uri? uri) =>
    uri != null &&
    uri.scheme == sosWidgetUriScheme &&
    uri.host == shakesosUriHost;

/// Whether [uri] is a Quick Settings tile-triggered SOS launch (also arms).
bool isTileSosUri(Uri? uri) =>
    uri != null &&
    uri.scheme == sosWidgetUriScheme &&
    uri.host == tileSosUriHost;

/// Routes a launch URI to the SOS screen and, for arming triggers (shake
/// detection, QS tile), invokes [onEmergencyTrigger] — which calls the single
/// SOS activation seam. No-op until the router is up.
void routeLaunch(Uri? uri, void Function(Uri)? onEmergencyTrigger) {
  if (uri == null) return;
  final router = publishedRouter;
  if (router == null) {
    debugPrint('Home widget routing: launch $uri ignored, router not ready');
    return;
  }
  if (isSosWidgetUri(uri) || isShakeSosUri(uri) || isTileSosUri(uri)) {
    debugPrint('Home widget routing: navigating to SOS from $uri');
    router.go(AppRoutes.sos);
  }
  if (isShakeSosUri(uri) || isTileSosUri(uri)) {
    debugPrint('Emergency trigger from $uri: arming the SOS workflow');
    onEmergencyTrigger?.call(uri);
  }
}

/// Routes a warm-start launch (app already running) from the home-screen SOS
/// widget, the shake detector or the QS tile.
void routeWidgetLaunch(Uri? uri) => routeLaunch(uri, null);

/// Routes a cold-start launch (app opened from the widget, the shake detector
/// or the QS tile), waiting up to 5 seconds for the router to be published.
Future<void> routeFromWidgetLaunch(void Function(Uri)? onEmergencyTrigger) async {
  final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
  if (uri == null) return;
  for (var i = 0; i < 100 && publishedRouter == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  routeLaunch(uri, onEmergencyTrigger);
}

/// Registers launch routing for both cold and warm starts. Call once after
/// the binding is initialized (e.g. in the app's initState). [onEmergencyTrigger]
/// arms the SOS workflow when the launch came from an arming trigger (shake
/// detector or QS tile); widget taps navigate only.
Future<void> setupWidgetLaunchRouting({
  void Function(Uri uri)? onEmergencyTrigger,
}) async {
  HomeWidget.widgetClicked.listen((uri) => routeLaunch(uri, onEmergencyTrigger));
  await routeFromWidgetLaunch(onEmergencyTrigger);
}

/// Whether the platform can pin widgets from the app (Android 8+).
Future<bool> canPinSosWidget() async {
  return await HomeWidget.isRequestPinWidgetSupported() ?? false;
}

/// Asks the launcher to pin the SOS widget to the home screen. Completes once
/// the system pin flow has been shown.
Future<void> pinSosWidget() async {
  await HomeWidget.requestPinWidget(
    qualifiedAndroidName: sosWidgetProviderName,
  );
}