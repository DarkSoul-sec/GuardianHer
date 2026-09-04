import 'package:flutter/services.dart';

import '../../core/platform/battery_service.dart';

class BatteryServiceImpl implements BatteryService {
  const BatteryServiceImpl();

  static const MethodChannel _channel = MethodChannel('guardianher/battery');

  @override
  Future<int?> getBatteryLevel() async {
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel');
      return level;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool?> isCharging() async {
    try {
      final charging = await _channel.invokeMethod<bool>('isCharging');
      return charging;
    } on PlatformException {
      return null;
    }
  }
}