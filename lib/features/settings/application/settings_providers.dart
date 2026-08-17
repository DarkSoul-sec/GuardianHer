import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/settings_repository_impl.dart';
import '../domain/security_settings.dart';
import '../domain/settings_repository.dart';
import 'security_settings_controller.dart';

/// Binds the settings repository to preferences storage.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(
    preferences: ref.watch(preferencesServiceProvider),
  ),
);

/// Security settings controller.
final securitySettingsControllerProvider =
    NotifierProvider<SecuritySettingsController, SecuritySettings>(
  SecuritySettingsController.new,
);