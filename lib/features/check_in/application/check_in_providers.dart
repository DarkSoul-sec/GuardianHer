import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/local_notifications.dart';
import '../../../core/providers.dart';
import '../data/flutter_local_notifications_check_in_scheduler.dart';
import '../data/preferences_check_in_settings_repository.dart';
import '../data/cascade_check_in_message_sender.dart';
import '../domain/check_in_message_sender.dart';
import '../domain/check_in_scheduler.dart';
import '../domain/check_in_settings_repository.dart';
import 'check_in_controller.dart';
import 'check_in_state.dart';

/// Injected clock for all check-in timeline timestamps (replace in tests).
final checkInClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Binds check-in settings storage to preferences.
final checkInSettingsRepositoryProvider = Provider<CheckInSettingsRepository>(
  (ref) => PreferencesCheckInSettingsRepository(
    ref.watch(preferencesServiceProvider),
  ),
);

/// Binds reminder scheduling to the shared local-notifications plugin.
final checkInSchedulerProvider = Provider<CheckInScheduler>(
  (ref) => FlutterLocalNotificationsCheckInScheduler(
    plugin: ref.watch(flutterLocalNotificationsPluginProvider),
  ),
);

/// Delivery seam (Phase 3G): user-confirmed cascade SMS → email → share.
final checkInMessageSenderProvider = Provider<CheckInMessageSender>(
  (ref) => const CascadeCheckInMessageSender(),
);

/// The Safety Check-In controller.
final checkInControllerProvider =
    NotifierProvider<CheckInController, CheckInState>(
  CheckInController.new,
);