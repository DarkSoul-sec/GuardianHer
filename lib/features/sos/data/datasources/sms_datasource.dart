import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsDataSource {
  final Telephony telephony = Telephony.instance;

  Future<bool> ensureSmsPermission() async {
    // For API 36, permission_handler is the source of truth
    var smsStatus = await Permission.sms.status;
    if (!smsStatus.isGranted) {
      smsStatus = await Permission.sms.request();
    }
    
    var phoneStatus = await Permission.phone.status;
    if (!phoneStatus.isGranted) {
      phoneStatus = await Permission.phone.request();
    }

    // Telephony also needs its internal permission
    final bool? telephonyPerms = await telephony.requestPhoneAndSmsPermissions;
    
    return smsStatus.isGranted && telephonyPerms == true;
  }

  Future<bool> sendAutoSms({required String to, required String message}) async {
    final hasPerm = await ensureSmsPermission();
    if (!hasPerm) {
      print("SMS Permission denied by user");
      return false;
    }

    try {
      await telephony.sendSms(
        to: to,
        message: message,
        isMultipart: true,
      );
      return true;
    } catch (e) {
      print("Auto SMS failed: $e");
      return false;
    }
  }
}