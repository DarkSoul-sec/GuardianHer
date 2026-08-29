import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../data/preferences_service_impl.dart';
import '../../../data/secure_storage_service_impl.dart';
import '../../location/data/location_manager_location_service.dart';
import '../../contacts/data/contacts_repository_impl.dart';
import '../data/cascade_check_in_message_sender.dart';
import '../data/flutter_local_notifications_check_in_scheduler.dart';
import '../data/preferences_check_in_settings_repository.dart';
import 'check_in_execution_service.dart';

/// True while a check-in execution is running in THIS isolate.
bool _backgroundRunInFlight = false;

/// Background-notification entrypoint for scheduled check-in EXECUTIONS.
///
/// Registered as `onDidReceiveBackgroundNotificationResponse` by
/// `ensureLocalNotificationsInitialized` (wired from `main.dart`). Runs in a
/// headless isolate: NO Riverpod, NO widgets — every dependency is built by
/// hand from plain constructors. Platform-channel plugins are available here
/// (flutter registers them per-isolate).
///
/// The pipeline is identical to the foreground path; only what Android allows
/// differs. If background location access is refused, the outcome records the
/// restriction honestly and the notification remains for the user to tap.
@pragma('vm:entry-point')
Future<void> handleSafetyCheckInBackground(NotificationResponse response) async {
  if (response.payload != checkInExecutionPayload || _backgroundRunInFlight) {
    return;
  }
  _backgroundRunInFlight = true;
  if (kDebugMode) {
    debugPrint('[CheckInExecution] background isolate entered');
  }
  try {
    final scheduler = FlutterLocalNotificationsCheckInScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    if (kDebugMode) {
      debugPrint('[CheckInExecution] background pipeline starting');
    }
    await runScheduledCheckIn(      CheckInExecutionSeams(
        settingsRepository: const PreferencesCheckInSettingsRepository(
          SharedPreferencesService(),
        ),
        locationService: LocationManagerLocationService(),
        messageSender: const CascadeCheckInMessageSender(),
        contactsRepository: const SecureStorageContactsRepository(
          storage: FlutterSecureStorageService(),
        ),
        now: DateTime.now,
        // SOS lives in the main isolate; a run that fires while the app is
        // dead cannot collide with an in-app SOS session. When the app IS
        // alive, runs go through the controller, which checks real SOS state.
        isSosActive: () => false,
        scheduleNextExecution: scheduler.scheduleExecution,
      ),
    );
  } catch (error) {
    if (kDebugMode) {
      debugPrint('[CheckInExecution] background run failed: $error');
    }
  } finally {
    _backgroundRunInFlight = false;
  }
}
