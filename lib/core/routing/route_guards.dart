import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/permissions/permission_service.dart';

class RouteGuards {
  static const String onboardingDoneKey = 'onboarding_done';

  static Future<bool> isOnboardingRequired({
    PermissionService? permissionService,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(onboardingDoneKey) ?? false;

    // Check critical permissions - use injected service for tests, fall back to
    // platform permission_handler for production.
    bool locationGranted;
    bool smsGranted;
    bool notificationGranted;

    if (permissionService != null) {
      locationGranted = (await permissionService.status(AppPermission.location))
          == PermissionStatus.granted;
      smsGranted = (await permissionService.status(AppPermission.sms))
          == PermissionStatus.granted;
      notificationGranted = (await permissionService.status(AppPermission.notifications))
          == PermissionStatus.granted;
    } else {
      locationGranted = await ph.Permission.locationWhenInUse.isGranted;
      smsGranted = await ph.Permission.sms.isGranted;
      notificationGranted = await ph.Permission.notification.isGranted;
    }

    // If onboarding never done OR critical permission revoked -> show onboarding
    if (!done) return true;
    if (!locationGranted || !smsGranted || !notificationGranted) {
      return true;
    }
    return false;
  }

  static Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingDoneKey, true);
  }
}