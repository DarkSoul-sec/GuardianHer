import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/home_widget.dart';
import '../core/platform/local_notifications.dart';
import '../core/platform/shake_sos_service.dart';
import '../core/providers.dart';
import '../features/safety_recorder/application/safety_recorder_controller.dart';
import '../features/journey/domain/safety_recorder_events.dart';
import '../features/sos/application/sos_providers.dart';
import '../features/journey/application/journey_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root application widget.
class GuardianHerApp extends ConsumerStatefulWidget {
  const GuardianHerApp({super.key});

  @override
  ConsumerState<GuardianHerApp> createState() => _GuardianHerAppState();
}

class _GuardianHerAppState extends ConsumerState<GuardianHerApp> {
  @override
  void initState() {
    super.initState();
    // Routes launches from the home-screen SOS widget, the shake detector and
    // the Quick Settings SOS tile. Requires the binding to be initialized,
    // hence initState rather than main(). Shake/tile launches also arm the SOS
    // workflow through the single startSos() seam.
    setupWidgetLaunchRouting(
      onEmergencyTrigger: (uri) {
        if (isShakeSosUri(uri)) {
          ref.read(safetyRecorderProvider.notifier).recordEvent(
            eventType: SafetyEventType.shakeDetected,
            sessionId: '',
          );
        }
        ref.read(sosControllerProvider.notifier).startSos();
      },
    );
    // Warm-start intent forwarding: when the app is already running and
    // ShakeSosService/SosTileService launches MainActivity with a URI,
    // Android delivers it via onNewIntent → MethodChannel → here.
    // Without this listener the URI is silently dropped and SOS never activates.
    const MethodChannel('guardianher/sos_trigger').setMethodCallHandler(
      (call) async {
        if (call.method == 'onNewIntent') {
          final uriString = call.arguments as String?;
          debugPrint('[GuardianHer][SosTrigger] MethodChannel received: method=${call.method}, arg=$uriString');
          if (uriString == null) return;
          final uri = Uri.parse(uriString);
          debugPrint('Warm-start intent received: $uri');
          // Wait for router to be published (may not be ready during cold start).
          for (var i = 0; i < 100 && publishedRouter == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          debugPrint('[GuardianHer][SosTrigger] Router ready=${publishedRouter != null}');
          routeLaunch(uri, (triggerUri) {
            debugPrint('[GuardianHer][SosTrigger] routeLaunch callback: startSos()');
            if (isShakeSosUri(triggerUri) || isTileSosUri(triggerUri)) {
              ref.read(safetyRecorderProvider.notifier).recordEvent(
                eventType: SafetyEventType.shakeDetected,
                sessionId: '',
              );
            }
            ref.read(sosControllerProvider.notifier).startSos();
          });
        }
      },
    );
    // If the app is (re)starting after the process was killed mid-SOS, the
    // shake service may still be running a native alert loop from the previous
    // session. Clear it so vibration never restarts from a dead session, and
    // drop any leftover location foreground context. The coordinate-free
    // location snapshot of that dead session is cleared too: leftovers must
    // never look like live data (Phase 3I).
    if (isShakeSosSupported) {
      ref.read(shakeSosServiceProvider).stopSosAlert();
      ref.read(sosLocationServiceProvider).stop();
    }
    unawaited(
      ref.read(sosLocationSessionStoreProvider).clear(),
    );
    // Initialize the shared notification plugin at startup: a tap that
    // LAUNCHED the app is only reported through getNotificationAppLaunchDetails
    // during initialization, and lazily-initialized consumers would miss it.
    ensureLocalNotificationsInitialized(
      ref.read(flutterLocalNotificationsPluginProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Keep the SOS side-effect coordinator alive for the WHOLE app lifetime,
    // not just while the SOS screen is mounted. Cold-start emergency triggers
    // (QS tile, shake detector, home-screen widget) arm SOS from the launch-
    // routing callback BEFORE any screen exists; with instant activation the
    // session can go countdown→active before SosScreen ever builds, and a
    // screen-scoped coordinator would miss every transition (no vibration, no
    // alert notification, no location context, no QS tile mirror). Watching it
    // here subscribes its internal listeners from the very first frame.
    ref.watch(sosActionsControllerProvider);
    // App-rooted emergency orchestrator: watches SOS lifecycle and orchestrates
    // automatic SMS dispatch to guardians, GPS acquisition, battery collection,
    // delivery tracking and retry. Must be alive before any SOS trigger can arm.
    ref.watch(emergencyOrchestratorProvider);
    // App-rooted journey lifecycle: escalation on shake must work from any
    // screen, exactly like the SOS side-effect coordinator above.
    ref.watch(journeyControllerProvider);
    // App-rooted safety recorder: observes SOS and journey to record
    // privacy-safe events into incidents. Never blocks or delays SOS/journey.
    ref.watch(safetyRecorderProvider);

    return MaterialApp.router(
      title: 'GuardianHer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
    );
  }
}