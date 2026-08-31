import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_info_service_impl.dart';
import '../data/call_service_impl.dart';
import '../data/data_cleanup_service_impl.dart';
import '../data/direct_sms_service_impl.dart';
import '../data/email_service_impl.dart';
import '../data/emergency_sms_bridge_impl.dart';
import '../data/live_sharing_service_impl.dart';
import '../data/map_service_impl.dart';
import '../data/notification_service_impl.dart';
import '../data/permission_service_impl.dart';
import '../data/preferences_service_impl.dart';
import '../data/secure_storage_service_impl.dart';
import '../data/share_service_impl.dart';
import '../data/sms_service_impl.dart';
import '../data/vibration_service_impl.dart';
import '../data/whatsapp_service_impl.dart';
import '../features/location/data/location_manager_location_service.dart';
import 'permissions/permission_service.dart';
import 'platform/app_info_service.dart';
import 'platform/call_service.dart';
import 'platform/device_admin_service.dart';
import 'platform/direct_sms_service.dart';
import 'platform/email_service.dart';
import 'platform/emergency_sms_bridge.dart';
import 'platform/live_location_platform.dart';
import 'platform/local_notifications.dart';
import 'platform/location_service.dart';
import 'platform/live_sharing_service.dart';
import 'platform/map_service.dart';
import 'platform/notification_service.dart';
import 'platform/preferences_service.dart';
import 'platform/share_service.dart';
import 'platform/shake_sos_service.dart';
import 'platform/sms_service.dart';
import 'platform/sos_location_service.dart';
import 'platform/sos_tile.dart';
import 'platform/vibration_service.dart';
import 'platform/whatsapp_service.dart';
import 'security/data_cleanup_service.dart';
import 'security/secure_storage_service.dart';

/// Dependency injection wiring for core platform services.
///
/// This file is the composition root: abstract service interfaces are bound to
/// their data-layer implementations here. Tests override these providers with
/// fakes so no plugin platform channel is touched.
final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => const FlutterSecureStorageService(),
);

final preferencesServiceProvider = Provider<PreferencesService>(
  (ref) => const SharedPreferencesService(),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionServiceImpl(),
);

final appInfoServiceProvider = Provider<AppInfoService>(
  (ref) => const PackageInfoAppInfoService(),
);

/// App identity (name, version, build number).
final appInfoProvider = FutureProvider<AppInfo>(
  (ref) => ref.watch(appInfoServiceProvider).getAppInfo(),
);

final dataCleanupServiceProvider = Provider<DataCleanupService>(
  (ref) => DataCleanupServiceImpl(
    secureStorage: ref.watch(secureStorageServiceProvider),
    preferences: ref.watch(preferencesServiceProvider),
  ),
);

/// Services below are wired to their plugin-backed implementations and remain
/// overridable in tests.
final locationServiceProvider = Provider<LocationService>(
  // GMS-free native LocationManager engine (F-Droid-first Phase 3H-1).
  (ref) => LocationManagerLocationService(),
);

final callServiceProvider = Provider<CallService>(
  (ref) => const UrlLauncherCallService(),
);

final smsServiceProvider = Provider<SmsService>(
  (ref) => const UrlLauncherSmsService(),
);

/// Direct SMS sending via native SmsManager (emergency orchestrator only).
/// Requires SEND_SMS runtime permission; the orchestrator requests it before
/// attempting any send. Falls back gracefully when denied.
final directSmsServiceProvider = Provider<DirectSmsService>(
  (ref) => MethodChannelDirectSmsService(
    permissions: ref.watch(permissionServiceProvider),
  ),
);

/// Email composer (Phase 3G): user-confirmed mailto: fallback channel.
final emailServiceProvider = Provider<EmailService>(
  (ref) => const UrlLauncherEmailService(),
);

/// System share sheet (Phase 3G): last-resort delivery channel.
final shareServiceProvider = Provider<ShareService>(
  (ref) => const SharePlusShareService(),
);

/// Pre-filled WhatsApp chat opener (Phase 3I). Opens WhatsApp for one
/// deliberate, user-initiated share; never sends anything itself.
final whatsappServiceProvider = Provider<WhatsAppService>(
  (ref) => const UrlLauncherWhatsAppService(),
);

final mapServiceProvider = Provider<MapService>(
  (ref) => const UrlLauncherMapService(),
);

/// SOS vibration. The default notification provider is wired with tap
/// navigation in `main.dart`, which owns app routing.
final vibrationServiceProvider = Provider<VibrationService>(
  (ref) => const VibrationServiceVibration(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => FlutterLocalNotificationsNotificationService(
    plugin: ref.watch(flutterLocalNotificationsPluginProvider),
  ),
);

/// Native shake-detection foreground service (Android only; guarded by the
/// feature controller so other platforms never touch the channel).
final shakeSosServiceProvider = Provider<ShakeSosService>(
  (ref) => const ShakeSosServiceChannel(),
);

/// Foreground location context held only while SOS is active (Android only;
/// guarded by the SOS flow so other platforms never touch the channel). This is
/// the documented alternative to ACCESS_BACKGROUND_LOCATION, which is
/// intentionally not requested.
final sosLocationServiceProvider = Provider<SosLocationService>(
  (ref) => const SosLocationServiceChannel(),
);

/// Quick Settings SOS tile state mirror (Android only; guarded by the SOS flow
/// so other platforms never touch the channel).
final sosTileStateServiceProvider = Provider<SosTileStateService>(
  (ref) => const SosTileStateServiceChannel(),
);

/// Android device-administrator status/activation (Android only; the Settings
/// screen hides the feature on other platforms).
final deviceAdminServiceProvider = Provider<DeviceAdminService>(
  (ref) => const DeviceAdminServiceChannel(),
);

/// Location-type foreground service holding the location context while a
/// LIVE-LOCATION session is active (Android only; Phase 3J). Same pattern as
/// [sosLocationServiceProvider]; separate service so SOS stays untouched.
final liveLocationForegroundServiceProvider =
    Provider<LiveLocationForegroundService>(
  (ref) => const LiveLocationForegroundServiceChannel(),
);

/// Native continuous location fixes (requestLocationUpdates on GPS+NETWORK)
/// streamed over guardianher/location_updates while a live session runs.
final liveLocationUpdatesProvider = Provider<LiveLocationUpdates>(
  (ref) => LiveLocationUpdatesChannel(),
);

/// Native Android emergency SMS bridge. Delegates critical SMS-sending to a
/// foreground service that survives MainActivity destruction. Used exclusively
/// by EmergencyOrchestrator; user-initiated SMS uses [smsServiceProvider].
final nativeEmergencySmsBridgeProvider = Provider<NativeEmergencySmsBridge>(
  (ref) => MethodChannelEmergencySmsBridge(),
);

/// Native Android live sharing service. Runs a foreground service that sends
/// periodic location updates via SMS to emergency contacts. No server needed.
final liveSharingServiceProvider = Provider<LiveSharingService>(
  (ref) => MethodChannelLiveSharingService(),
);
