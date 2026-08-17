import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/application/settings_providers.dart';
import '../../../settings/domain/app_lock_delay.dart';
import '../../application/app_lock_providers.dart';

/// Locks the app when it returns from the background according to the
/// configured [AppLockDelay] security setting.
///
/// No background service is involved; this uses the standard lifecycle
/// observer API.
class AppLifecycleObserver extends ConsumerStatefulWidget {
  const AppLifecycleObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pre-load the security settings so the first lifecycle event observes the
    // configured lock delay instead of the unloaded default.
    ref.read(securitySettingsControllerProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
        if (ref.read(securitySettingsControllerProvider).lockDelay ==
            AppLockDelay.immediate) {
          ref.read(appLockControllerProvider.notifier).lock();
        }
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        if (backgroundedAt != null &&
            ref.read(appLockControllerProvider).isUnlocked) {
          final delay = ref.read(securitySettingsControllerProvider).lockDelay;
          final duration = delay.duration;
          final elapsed = DateTime.now().difference(backgroundedAt);
          if (duration != null && elapsed >= duration) {
            ref.read(appLockControllerProvider.notifier).lock();
          }
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}