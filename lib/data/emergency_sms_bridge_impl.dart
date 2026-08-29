import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/platform/emergency_sms_bridge.dart';

/// MethodChannel-backed implementation of [NativeEmergencySmsBridge].
///
/// Communication:
///   Dart → Kotlin: `guardianher/emergency_sms` channel, `startEmergency` method.
///   Kotlin → Dart: same channel, `onGuardianStatusChanged` / `onEmergencyComplete`
///                  invoked from the foreground service.
class MethodChannelEmergencySmsBridge implements NativeEmergencySmsBridge {
  static const _channel = MethodChannel('guardianher/emergency_sms');

  final _statusController = StreamController<EmergencySmsStatusUpdate>.broadcast();
  final _completionController = StreamController<EmergencySmsCompleteEvent>.broadcast();
  bool _handlerRegistered = false;

  MethodChannelEmergencySmsBridge() {
    _registerHandler();
  }

  void _registerHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onGuardianStatusChanged':
          final args = call.arguments as Map<Object?, Object?>;
          final guardianId = args['guardianId'] as String? ?? '';
          final status = args['status'] as String? ?? '';
          final error = args['error'] as String?;
          _statusController.add(EmergencySmsStatusUpdate(
            guardianId: guardianId,
            status: status,
            error: error,
          ));
        case 'onEmergencyComplete':
          final args = call.arguments as Map<Object?, Object?>;
          final sosEventId = args['sosEventId'] as String? ?? '';
          final sent = args['sent'] as int? ?? 0;
          final failed = args['failed'] as int? ?? 0;
          _completionController.add(EmergencySmsCompleteEvent(
            sosEventId: sosEventId,
            totalSent: sent,
            totalFailed: failed,
          ));
      }
    });
  }

  @override
  Future<void> startEmergency({
    required String sosEventId,
    required List<EmergencyGuardianData> guardians,
    required String smsBody,
    String? locationUrl,
    int? batteryPercentage,
  }) async {
    final guardiansJson = jsonEncode(
      guardians.map((g) => g.toMap()).toList(),
    );

    await _channel.invokeMethod<void>('startEmergency', {
      'sosEventId': sosEventId,
      'guardiansJson': guardiansJson,
      'smsBody': smsBody,
      'locationUrl': locationUrl,
      'batteryPercentage': batteryPercentage,
    });
  }

  @override
  Future<void> cancelEmergency() async {
    try {
      await _channel.invokeMethod<void>('cancelEmergency');
    } on PlatformException {
      // Best-effort cancellation.
    }
  }

  @override
  Future<bool> checkSmsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkSmsPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestSmsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestSmsPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<int?> getBatteryPercentage() async {
    try {
      final result = await _channel.invokeMethod<int>('getBatteryPercentage');
      return result;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<EmergencySmsStatusUpdate> get statusUpdates =>
      _statusController.stream;

  @override
  Stream<EmergencySmsCompleteEvent> get completionEvents =>
      _completionController.stream;

  void dispose() {
    _statusController.close();
    _completionController.close();
  }
}
