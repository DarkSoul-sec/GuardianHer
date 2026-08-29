import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/shake_sos_service.dart';
import '../../../core/providers.dart';
import '../application/shake_sos_providers.dart';
import '../domain/oem_background_guidance.dart';

/// Whether the user has granted "Display over other apps" (`SYSTEM_ALERT_WINDOW`).
final shakeSosOverlayProvider = FutureProvider<bool>((ref) {
  return ref.watch(shakeSosServiceProvider).canDrawOverlays();
});

/// Whether Android currently exempts GuardianHer from battery optimization.
final shakeSosBatteryWhitelistedProvider = FutureProvider<bool>((ref) {
  return ref.watch(shakeSosServiceProvider).isIgnoringBatteryOptimizations();
});

/// Manufacturer token for OEM-specific background guidance (may be null).
final shakeSosManufacturerTokenProvider = FutureProvider<String?>((ref) {
  return ref.watch(shakeSosServiceProvider).manufacturerToken();
});

/// Shake SOS settings.
///
/// Enabling starts a foreground service that keeps listening to the
/// accelerometer even while the app is closed, so a deliberate shake (three
/// quick shakes in a row) arms SOS from anywhere. The service shows a small
/// persistent notification.
///
/// Two opt-in grants make closed-app detection actually work on stock Android:
///  * battery-optimization whitelist (Redmi/MIUI kills the service otherwise);
///  * "Display over other apps" (`SYSTEM_ALERT_WINDOW`), the documented
///    exemption that lets a detected shake bring the app to the foreground.
///    Without it, Android silently refuses the background launch (`BAL_BLOCK`).
class ShakeSosSettingsScreen extends ConsumerStatefulWidget {
  const ShakeSosSettingsScreen({super.key});

  @override
  ConsumerState<ShakeSosSettingsScreen> createState() =>
      _ShakeSosSettingsScreenState();
}

class _ShakeSosSettingsScreenState extends ConsumerState<ShakeSosSettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh after the user returns from the battery/overlay settings pages.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(shakeSosOverlayProvider);
      ref.invalidate(shakeSosBatteryWhitelistedProvider);
      ref.invalidate(shakeSosManufacturerTokenProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(shakeSosEnabledProvider);
    final overlayGranted = ref.watch(shakeSosOverlayProvider);
    final batteryWhitelisted = ref.watch(shakeSosBatteryWhitelistedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shake SOS')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Shake to trigger SOS'),
            subtitle: const Text(
              'Shake your phone three times quickly to start the emergency '
              'workflow, even when the app is closed.',
            ),
            value: enabled,
            onChanged: enabled || isShakeSosSupported
                ? (value) => ref
                    .read(shakeSosEnabledProvider.notifier)
                    .setEnabled(value)
                : null,
          ),
          if (enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'While enabled, GuardianHer shows a small persistent '
                'notification and monitors motion in the background. The '
                'detector only reacts to a deliberate shake pattern.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'The detector restarts automatically after your phone reboots '
                'or GuardianHer is updated.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Divider(),
          if (isShakeSosSupported)
            ..._grantsSection(theme, overlayGranted, batteryWhitelisted),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('How it works'),
            subtitle: const Text(
              'The detector counts three quick shakes within two seconds and '
              'then starts SOS immediately. It pauses for a few seconds after '
              'a trigger to avoid repeats.',
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _grantsSection(
    ThemeData theme,
    AsyncValue<bool> overlayGranted,
    AsyncValue<bool> batteryWhitelisted,
  ) {
    return [
      ListTile(
        leading: const Icon(Icons.battery_alert_outlined),
        title: const Text('Battery optimization'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            batteryWhitelisted.when(
              data: (whitelisted) => Text(
                whitelisted
                    ? 'Allowed to run in the background without restrictions.'
                    : 'Not protected yet — Android may stop the detector to '
                        'save power.',
              ),
              loading: () => const Text('Checking status…'),
              error: (_, _) => const Text('Could not check this status.'),
            ),
            if (ref.watch(shakeSosManufacturerTokenProvider).valueOrNull
                case final String token)
              if (oemBackgroundGuidance(token) case final String hint)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(hint),
                ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => ref
            .read(shakeSosServiceProvider)
            .openBatteryOptimizationSettings(),
      ),
      ListTile(
        leading: const Icon(Icons.layers_outlined),
        title: const Text('Display over other apps'),
        subtitle: overlayGranted.when(
          data: (granted) => Text(
            granted
                ? 'Granted. Shake SOS can open the app even when it is fully '
                    'closed.'
                : 'Required to open the app from a shake when it is fully '
                    'closed (Android blocks this otherwise).',
          ),
          loading: () => const Text('Checking permission…'),
          error: (_, _) => const Text('Could not check this permission.'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => ref
            .read(shakeSosServiceProvider)
            .openOverlaySettings(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Granting "Display over other apps" never shows an overlay — it only '
          'tells Android to allow the shake detector to open the SOS screen '
          'from the background.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }
}