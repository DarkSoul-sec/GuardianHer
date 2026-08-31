import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RouteGuards {
  static const String onboardingDoneKey = 'onboarding_done';

  static Future<bool> isOnboardingRequired() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(onboardingDoneKey) ?? false;

    // Check critical permissions
    final locationGranted = await Permission.locationWhenInUse.isGranted;
    final smsGranted = await Permission.sms.isGranted;
    final notificationGranted = await Permission.notification.isGranted;

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