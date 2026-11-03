import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router/app_router.dart';
import 'core/platform/local_notifications.dart';
import 'features/check_in/application/check_in_background_entrypoint.dart';
import 'features/check_in/data/flutter_local_notifications_check_in_scheduler.dart';
import 'features/fake_call/data/fake_call_notifier_impl.dart';

void main() {
  // Routes notification taps (SOS and check-in) to the right screen. The app
  // entrypoint owns routing; the check-in scheduler and SOS service share one
  // plugin and both dispatch through this handler.
  //
  // A COLD notification launch dispatches during plugin initialization,
  // before runApp publishes the router — so wait for publication (same
  // pattern as setupWidgetLaunchRouting) instead of dropping the route.
  localNotificationsTapHandler = (payload) async {
    final route =
        payload == checkInNotificationPayload || payload == checkInExecutionPayload
            ? AppRoutes.checkIn
            : payload == fakeCallNotificationPayload
                ? '${AppRoutes.fakeCall}?incoming=true'
                : AppRoutes.sos;
    for (var i = 0; i < 100 && publishedRouter == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    publishedRouter?.go(route);
  };
  // Scheduled check-in EXECUTIONS wake a headless isolate through this
  // dispatcher when an alarm fires while the app is dead. Must be assigned
  // before the first consumer initializes the shared plugin.
  localNotificationsBackgroundHandler = handleSafetyCheckInBackground;
  runApp(const ProviderScope(child: GuardianHerApp()));
}