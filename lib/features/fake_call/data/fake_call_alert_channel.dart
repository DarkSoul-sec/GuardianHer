import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/fake_call_alert.dart';


/// Release-safe logging: diagnostic output only, never in production builds.
/// Call sites log metadata (counts, states, durations) — never phone numbers,
/// message bodies, coordinates, names, or file contents.
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}


/// [FakeCallAlertService] over the isolated `guardianher/fake_call` channel.
///
/// Native side loops the system default ringtone and (optionally) a vibration
/// waveform, all stopped idempotently. Never throws: channel failures resolve
/// silently so a missing native handler can never break the state machine.
class MethodChannelFakeCallAlert implements FakeCallAlertService {
  const MethodChannelFakeCallAlert();

  static const MethodChannel _channel = MethodChannel('guardianher/fake_call');

  @override
  Future<void> startAlert({required bool vibrate}) async {
    try {
      await _channel.invokeMethod<void>('startAlert', {'vibrate': vibrate});
    } on Exception catch (e) {
      _log('[FakeCall] startAlert failed: $e');
    }
  }

  @override
  Future<void> stopAlert() async {
    try {
      await _channel.invokeMethod<void>('stopAlert');
    } on Exception catch (e) {
      _log('[FakeCall] stopAlert failed: $e');
    }
  }
}
