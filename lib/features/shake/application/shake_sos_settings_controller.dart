import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/preferences_service.dart';
import '../../../core/platform/shake_sos_service.dart';
import '../../../core/providers.dart';

/// Preference key for the Shake SOS enabled flag (non-sensitive).
const String shakeSosEnabledPreferenceKey = 'shake_sos_enabled';

/// Controls the Shake SOS detector.
///
/// Enabling starts the native foreground service (the only detector — it works
/// both while the app is open and while it is closed); disabling stops it.
/// The choice persists in preferences. On non-Android platforms the service is
/// not supported and the toggle is always off.
class ShakeSosSettingsController extends Notifier<bool> {
  ShakeSosService get _service => ref.read(shakeSosServiceProvider);
  PreferencesService get _preferences =>
      ref.read(preferencesServiceProvider);

  @override
  bool build() {
    // Restore the persisted choice asynchronously; the UI starts off and
    // flips to the stored value when the read completes.
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final stored = await _preferences.getBool(shakeSosEnabledPreferenceKey);
    if (stored != true) {
      return;
    }
    if (!isShakeSosSupported) {
      await _preferences.remove(shakeSosEnabledPreferenceKey);
      return;
    }
    // Re-anchor the service on app start in case the OS recycled it.
    await _service.start();
    state = true;
  }

  /// Turns the detector on (starts the foreground service) or off.
  Future<void> setEnabled(bool enabled) async {
    if (enabled && !isShakeSosSupported) {
      return;
    }
    if (enabled) {
      await _service.start();
    } else {
      await _service.stop();
    }
    await _preferences.setBool(shakeSosEnabledPreferenceKey, enabled);
    state = enabled;
  }
}