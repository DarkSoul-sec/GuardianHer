import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../location/application/location_providers.dart';
import '../../location/application/location_state.dart';
import '../../location/domain/location_share_message.dart';
import '../domain/sos_event.dart';
import 'emergency_orchestrator.dart';
import 'sos_action_controller.dart';
import 'sos_actions_state.dart';
import 'sos_controller.dart';
import 'sos_location_session_store.dart';
import 'sos_state.dart';
import 'sos_timer.dart';

/// Injected clock used for all SOS timestamps (replace in tests).
final sosClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Injected SOS event id generator (replace in tests).
final sosEventIdGeneratorProvider =
    Provider<SosEventId Function()>((ref) => SosEventId.generate);

/// Length of the pre-activation countdown for new sessions.
///
/// Zero: SOS activates instantly on tap for fast, direct emergency access.
/// The countdown state still exists in the state machine (activation is simply
/// synchronous), so a future safety delay can be reintroduced here.
final sosCountdownDurationProvider = Provider<Duration>(
  (ref) => Duration.zero,
);

/// Countdown timer used by the controller.
final sosTimerProvider = Provider<SosTimer>((ref) => TimerSosTimer());

/// The SOS workflow controller.
final sosControllerProvider =
    NotifierProvider<SosController, SosState>(SosController.new);

/// Emergency services number dialed by the "Call emergency" button
/// (112 works across Europe and on most GSM networks worldwide).
final sosEmergencyNumberProvider = Provider<String>((ref) => '112');

/// Generic pre-filled body for SMS composed to a trusted contact. Contains no
/// personal data, location or names.
final sosSmsBodyProvider = Provider<String>(
  (ref) =>
      'I need help. This is an automated message from GuardianHer. Please contact me.',
);

/// Message body for the user-confirmed SOS message: the generic text plus a
/// shareable "current location" link when a fix was captured during the
/// session. Nothing is ever sent automatically; the composer is
/// opened for the user to review.
final sosMessageBodyProvider = Provider<String>((ref) {
  final base = ref.read(sosSmsBodyProvider);
  final location = ref.read(locationControllerProvider);
  final point = location.status == LocationStatus.captured
      ? location.point
      : null;

  final buffer = StringBuffer(base);
  if (point != null) {
    buffer.write('\nMy location: ${buildMapsShareUrl(point)}');
  }
  return buffer.toString();
});

/// Coordinates SOS side effects (vibration, notification, dialer, SMS).
final sosActionsControllerProvider =
    NotifierProvider<SosActionController, SosActionsState>(
  SosActionController.new,
);

/// Delay before a single automatic re-attempt of a location capture that ended
/// "unavailable" or "services-disabled" while SOS stays active. The first fix
/// after a shake with the phone locked often needs GPS to settle, and a user
/// being walked to the location switch needs a re-capture once they flip it. A
/// single retry avoids nagging loops; the SOS screen still shows a recovery
/// path for a denied permission, which a retry cannot fix.
final sosLocationRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

/// Preferences-backed store for the ACTIVE session's coordinate-free location
/// snapshot (Phase 3I). Written on every location state change while SOS is
/// active; cleared when the session ends and at app boot.
final sosLocationSessionStoreProvider = Provider<SosLocationSessionStore>(
  (ref) => SosLocationSessionStore(ref.watch(preferencesServiceProvider)),
);

/// Central coordinator for the emergency SOS workflow: GPS acquisition,
/// automatic SMS dispatch to guardians, delivery tracking, and retry.
final emergencyOrchestratorProvider =
    NotifierProvider<EmergencyOrchestrator, EmergencyOrchestratorState>(
  EmergencyOrchestrator.new,
);
