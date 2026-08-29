import 'package:flutter/services.dart';

class DeviceAdminDataSource {
  static const _channel = MethodChannel('com.guardianher/device_admin');

  Future<bool> isDeviceAdminActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isActive');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestDeviceAdminActivation() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestActivation');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> deactivateDeviceAdmin() async {
    try {
      await _channel.invokeMethod('deactivate');
    } on PlatformException {
      // ignore
    }
  }
}