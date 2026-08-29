import 'package:flutter/services.dart';

import '../core/permissions/permission_service.dart';
import '../core/platform/direct_sms_service.dart';

/// MethodChannel-backed implementation of [DirectSmsService].
///
/// Communicates with the native `SmsSendHandler` in MainActivity which uses
/// Android's `SmsManager` to send messages directly. Permission handling
/// delegates to the existing [PermissionService] which already maps
/// [AppPermission.sms] to the platform `SEND_SMS` permission.
class MethodChannelDirectSmsService implements DirectSmsService {
  MethodChannelDirectSmsService({required PermissionService permissions})
      : _permissions = permissions;

  static const _channel = MethodChannel('guardianher/send_sms');
  final PermissionService _permissions;

  @override
  Future<bool> checkSimReady() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkSimReady');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      final status = await _permissions.status(AppPermission.sms);
      return status == PermissionStatus.granted;
    } on Exception catch (e) {
      // permission_handler can throw on certain device states (e.g. no
      // activity). Return false so the orchestrator can request permission
      // instead of crashing the emergency workflow.
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final status = await _permissions.request(AppPermission.sms);
      return status == PermissionStatus.granted;
    } on Exception catch (e) {
      // Same rationale as hasPermission: a plugin failure during an
      // emergency must not crash the workflow.
      return false;
    }
  }

  @override
  Future<({bool success, String? error})> sendSms({
    required String phoneNumber,
    required String body,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'sendSms',
        {'phoneNumber': phoneNumber, 'body': body},
      );
      if (result == null) {
        return (success: false, error: 'No response from platform.');
      }
      final success = result['success'] as bool? ?? false;
      final error = result['error'] as String?;
      return (success: success, error: error);
    } on PlatformException catch (e) {
      return (success: false, error: e.message);
    } on Exception catch (e) {
      return (success: false, error: e.toString());
    }
  }

  @override
  Future<int?> getBatteryPercentage() async {
    try {
      return await _channel.invokeMethod<int>('getBatteryPercentage');
    } on PlatformException {
      return null;
    }
  }
}
