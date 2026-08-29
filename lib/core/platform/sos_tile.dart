import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the Quick Settings SOS tile state mirror is available.
bool get isSosTileSupported => defaultTargetPlatform == TargetPlatform.android;

/// Mirrors the authoritative SOS state onto the native Quick Settings tile
/// (Phase B). Dart writes a boolean; Kotlin never decides anything.
///
/// The tile reads the mirrored value in [onStartListening], so the state is
/// honest even when the app process is dead and the tile binds cold.
abstract interface class SosTileStateService {
  /// Marks the tile engaged ([engaged] true while countdown/active/cancelling)
  /// or idle. Fire-and-forget by design: failures must never touch the SOS
  /// flow.
  Future<void> setEngaged({required bool engaged});
}

/// Platform-channel implementation bound in [core/providers.dart].
class SosTileStateServiceChannel implements SosTileStateService {
  const SosTileStateServiceChannel();

  static const MethodChannel _channel = MethodChannel('guardianher/sos_tile');

  @override
  Future<void> setEngaged({required bool engaged}) async {
    await _channel.invokeMethod<void>('setSosEngaged', engaged);
  }
}
