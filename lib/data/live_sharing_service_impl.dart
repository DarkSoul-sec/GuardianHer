import 'package:flutter/services.dart';

import '../platform/live_sharing_service.dart';

/// MethodChannel implementation of [LiveSharingService].
///
/// Communicates with native [LiveSharingService] (Kotlin) which runs as
/// a foreground service sending location updates via SMS.
class MethodChannelLiveSharingService implements LiveSharingService {
  static const _channel = MethodChannel('guardianher/live_sharing');

  @override
  Future<bool> start({
    required List<String> contacts,
    int intervalSeconds = 30,
  }) async {
    try {
      final contactsJson = _toJsonArray(contacts);
      final result = await _channel.invokeMethod<bool>('start', {
        'contactsJson': contactsJson,
        'intervalSeconds': intervalSeconds,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException {
      // ignore
    }
  }

  @override
  Future<void> forceUpdate() async {
    try {
      await _channel.invokeMethod('forceUpdate');
    } on PlatformException {
      // ignore
    }
  }

  String _toJsonArray(List<String> items) {
    return '[${items.map((e) => '"$e"').join(',')}]';
  }
}