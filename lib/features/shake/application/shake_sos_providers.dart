import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shake_sos_settings_controller.dart';

/// Whether Shake SOS is enabled.
final shakeSosEnabledProvider =
    NotifierProvider<ShakeSosSettingsController, bool>(
  ShakeSosSettingsController.new,
);